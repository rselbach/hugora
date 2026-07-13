import Foundation
import AppKit
import Combine
import os

struct WorkspaceRef: Codable, Identifiable, Equatable {
    var id: String { path }
    let path: String
    let bookmarkData: Data

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum WorkspaceError: LocalizedError, Equatable {
    case notHugoSite
    case unsafeFileOperation(String)
    case staleWorkspaceReference(String)

    var errorDescription: String? {
        switch self {
        case .notHugoSite:
            "This folder doesn't appear to be a Hugo site. Expected hugo.toml, config.toml, or a config/ directory."
        case .unsafeFileOperation(let path):
            "Refusing to modify a file outside the workspace content directory: \(path)"
        case .staleWorkspaceReference(let path):
            "The saved reference to \(path) is no longer valid. The folder may have been moved or deleted."
        }
    }
}

/// Manages the currently open Hugo workspace and its content.
///
/// Handles workspace validation, security-scoped bookmarks, content scanning,
/// file operations (create, delete), and maintains a list of recently used
/// workspaces. Delegates Hugo CLI interaction via ``HugoContentCreator``.
@MainActor
final class WorkspaceStore: ObservableObject {
    private enum Timing {
        /// Debounce before reloading all sections after a content directory change.
        static let contentReloadDebounce: UInt64 = 250_000_000  // 250 ms
        /// Debounce before refreshing a single section after its directory changes.
        static let sectionRefreshDebounce: UInt64 = 150_000_000  // 150 ms
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "WorkspaceStore"
    )
    private static let isRunningTests = ProcessInfo.processInfo.arguments.contains {
        $0.contains(".xctest") || $0 == "--testing-library"
    }

    /// Content sections detected in the Hugo site (e.g., blog, posts).
    @Published private(set) var sections: [ContentSection] = []

    /// Loaded Hugo configuration for current workspace.
    @Published private(set) var hugoConfig: HugoConfig?

    /// URL of currently opened workspace folder.
    @Published private(set) var currentFolderURL: URL?

    /// Display name of current site (folder name).
    @Published private(set) var siteName: String?

    /// Recently opened workspaces (persisted via bookmarks).
    @Published var recentWorkspaces: [WorkspaceRef] = []

    /// Last workspace-related error (e.g., not a valid Hugo site).
    @Published var lastError: WorkspaceError?

    /// Whether a workspace operation (open, refresh, create) is in progress.
    @Published var isLoading: Bool = false

    /// Which file is highlighted in the sidebar list (selection state only).
    @Published var selectedFileURL: URL?

    /// Names of shortcodes the site defines (layouts/shortcodes, including
    /// themes), for the Insert Shortcode menu.
    @Published private(set) var siteShortcodes: [String] = []

    /// Every tag used across the site, for autocomplete.
    var allTags: [String] {
        Set(sections.flatMap(\.items).flatMap(\.tags)).sorted()
    }

    /// Every category used across the site, for autocomplete.
    var allCategories: [String] {
        Set(sections.flatMap(\.items).flatMap(\.categories)).sorted()
    }

    /// Callback invoked when a file should be opened in the editor.
    /// Wired up by ContentView so WorkspaceStore doesn't depend on EditorState.
    var onOpenFile: ((URL) -> Void)?

    private var securityScopedURL: URL?
    private let hugoContentCreator: any HugoContentCreator
    private static let newPostDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let defaultNewPostTitle = "New Post"
    private static let defaultNewPostSlug = "new-post"
    private let maxRecent = 10
    private var contentDirectoryWatcher: DispatchSourceFileSystemObject?
    private var sectionWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var contentWatcherReloadTask: Task<Void, Never>?
    private var sectionRefreshTasks: [String: Task<Void, Never>] = [:]
    private var lastSafetyWarning: String?

    /// The resolved URL of the Hugo content directory for the current workspace.
    ///
    /// Returns `nil` if no workspace is open or the resolved path escapes
    /// the workspace folder (security check).
    var contentDirectoryURL: URL? {
        guard let folder = currentFolderURL, let config = hugoConfig else { return nil }
        let candidate = folder.appendingPathComponent(config.contentDir).standardizedFileURL
        guard PathSafety.isSameOrDescendant(candidate, of: folder) else { return nil }
        return candidate
    }

    /// Initializes a new workspace store.
    ///
    /// - Parameter hugoContentCreator: Strategy for creating new content via Hugo CLI.
    init(hugoContentCreator: any HugoContentCreator = HugoCLIContentCreator()) {
        self.hugoContentCreator = hugoContentCreator
        loadRecentWorkspaces()
        restoreLastWorkspace()
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Open Folder

    /// Displays open panel for user to select a Hugo site folder.
    ///
    /// - Parameter directoryURL: Optional folder to preselect in the panel.
    func openFolderPanel(directoryURL: URL? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Hugo site folder"
        panel.prompt = "Open"
        if let directoryURL {
            panel.directoryURL = directoryURL
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openFolder(url)
        }
    }

    /// Opens a workspace from a path handed in from outside the app (the
    /// hugora:// URL scheme or launch arguments).
    ///
    /// Sandboxed builds can't read arbitrary paths, so this resolves in
    /// stages: already open → reuse the recents bookmark → open directly
    /// when readable → fall back to the open panel preselected on the
    /// folder, which grants access through user consent.
    func openFromExternalPath(_ url: URL) {
        let standardized = url.standardizedFileURL

        if let current = currentFolderURL,
            current.standardizedFileURL == standardized
        {
            return
        }

        if let ref = recentWorkspaces.first(where: {
            URL(fileURLWithPath: $0.path).standardizedFileURL == standardized
        }) {
            openRecent(ref)
            return
        }

        if FileManager.default.isReadableFile(atPath: standardized.path) {
            openFolder(standardized)
            return
        }

        openFolderPanel(directoryURL: standardized)
    }

    /// Opens a Hugo workspace at the given URL.
    ///
    /// Validates that the folder is a Hugo site, creates a security-scoped bookmark,
    /// and loads content sections.
    ///
    /// - Parameter url: The URL of the folder to open.
    func openFolder(_ url: URL) {
        lastError = nil
        lastSafetyWarning = nil
        isLoading = true

        // Validate before touching the current workspace: a failed open must
        // leave the existing workspace (scope, watchers, open document)
        // fully functional.
        guard validateHugoSite(at: url) else {
            isLoading = false
            lastError = .notHugoSite
            return
        }

        stopAccessingCurrentFolder()

        guard let bookmarkData = createBookmark(for: url) else {
            openFolderWithoutBookmark(url)
            return
        }

        saveCurrentBookmark(bookmarkData)
        addToRecent(url: url, bookmarkData: bookmarkData)
        startAccessingFolder(url)
        loadContent(from: url)
    }

    /// Opens a recently used workspace from its bookmark reference.
    ///
    /// Resolves the security-scoped bookmark, validates the site, and handles
    /// stale bookmarks by re-creating them.
    ///
    /// - Parameter ref: The workspace reference containing the bookmark data.
    func openRecent(_ ref: WorkspaceRef) {
        lastError = nil
        lastSafetyWarning = nil
        isLoading = true

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: ref.bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            Self.logger.error(
                "Failed to resolve bookmark for recent workspace \(ref.path): \(error.localizedDescription)")
            removeFromRecent(ref)
            isLoading = false
            lastError = .staleWorkspaceReference(ref.path)
            return
        }

        // Sandboxed builds can't stat anything inside the folder until the
        // security scope is active — start it before validating. Keep the
        // recents entry on failure: it may be transient (unmounted volume).
        // The current workspace is only torn down once the new one is valid.
        let scopeActive = url.startAccessingSecurityScopedResource()
        guard validateHugoSite(at: url) else {
            if scopeActive { url.stopAccessingSecurityScopedResource() }
            isLoading = false
            lastError = .notHugoSite
            return
        }

        stopAccessingCurrentFolder()

        guard isStale else {
            saveCurrentBookmark(ref.bookmarkData)
            promoteRecent(ref, resolvedURL: url, bookmarkData: ref.bookmarkData)
            adoptAccessedFolder(url, scopeActive: scopeActive)
            loadContent(from: url)
            return
        }

        if let newData = createBookmark(for: url) {
            promoteRecent(ref, resolvedURL: url, bookmarkData: newData)
            saveCurrentBookmark(newData)
        }

        adoptAccessedFolder(url, scopeActive: scopeActive)
        loadContent(from: url)
    }

    /// Closes the current workspace and clears all state.
    ///
    /// Stops accessing security-scoped resources and clears sections,
    /// config, and selection state.
    func closeWorkspace() {
        stopAccessingCurrentFolder()
        lastSafetyWarning = nil
        sections = []
        hugoConfig = nil
        currentFolderURL = nil
        siteName = nil
        lastError = nil
        isLoading = false
        siteShortcodes = []
        UserDefaults.standard.removeObject(forKey: DefaultsKey.workspaceBookmark)
    }

    /// Reloads the content list from the current workspace.
    ///
    /// Useful for detecting external changes to the workspace.
    func refreshPosts() {
        guard let url = currentFolderURL else { return }
        isLoading = true
        loadContent(from: url)
    }

    // MARK: - Open File

    /// Opens a content file in the editor.
    ///
    /// Updates selection and calls ``onOpenFile`` callback to notify the editor.
    ///
    /// - Parameter url: The URL of the file to open.
    func openFile(_ url: URL) {
        selectedFileURL = url
        onOpenFile?(url)
    }

    // MARK: - Create New Post

    /// Creates a new Hugo content post using Hugo CLI or fallback.
    ///
    /// Determines the target section (preferring "blog" or "posts"), generates
    /// a unique slug based on today's date, and uses Hugo CLI if available.
    /// Falls back to manual file creation if Hugo CLI is not found.
    ///
    /// - Note: The new post is automatically opened after creation.
    func createNewPost() {
        guard !isLoading else { return }

        guard let siteURL = currentFolderURL else {
            presentNewPostError("No Hugo site is open.")
            return
        }

        let sectionCandidates = newPostSectionCandidates()
        guard !sectionCandidates.isEmpty else {
            presentNewPostError("No content section found. Add a section folder under your Hugo content directory.")
            return
        }
        guard let targetSection = pickSectionForNewPost(from: sectionCandidates) else {
            return
        }

        isLoading = true
        let format = preferredNewPostFormat()
        let config = hugoConfig ?? .default
        let contentCreator = hugoContentCreator

        // The availability probe spawns `hugo version`; keep it off the main
        // actor so the UI doesn't stall on process launch.
        Task(priority: .userInitiated) { [weak self] in
            let shouldUseHugoCLI = await Task.detached(priority: .userInitiated) {
                contentCreator.isAvailable(at: siteURL)
            }.value

            guard let self else { return }
            guard self.currentFolderURL?.standardizedFileURL == siteURL.standardizedFileURL else {
                self.isLoading = false
                return
            }
            self.finishCreateNewPost(
                siteURL: siteURL,
                targetSection: targetSection,
                format: format,
                config: config,
                contentCreator: contentCreator,
                shouldUseHugoCLI: shouldUseHugoCLI
            )
        }
    }

    private func finishCreateNewPost(
        siteURL: URL,
        targetSection: ContentSection,
        format: ContentFormat,
        config: HugoConfig,
        contentCreator: any HugoContentCreator,
        shouldUseHugoCLI: Bool
    ) {
        let sectionDir = targetSection.url
        let date = Date()
        let datePrefix = Self.newPostDateFormatter.string(from: date)

        let baseSlug = Self.defaultNewPostSlug
        var slug = baseSlug
        var counter = 1

        func postExists(_ candidateSlug: String) -> Bool {
            let folderName = "\(datePrefix)-\(candidateSlug)"
            let folderURL = sectionDir.appendingPathComponent(folderName)
            let fileURL = sectionDir.appendingPathComponent("\(folderName).md")
            return FileManager.default.fileExists(atPath: folderURL.path)
                || FileManager.default.fileExists(atPath: fileURL.path)
        }

        while postExists(slug) {
            slug = "\(baseSlug)-\(counter)"
            counter += 1
        }

        let folderName = "\(datePrefix)-\(slug)"
        let folderURL = sectionDir.appendingPathComponent(folderName)
        let expectedFileURL: URL
        switch format {
        case .bundle:
            expectedFileURL = folderURL.appendingPathComponent("index.md")
        case .file:
            expectedFileURL = sectionDir.appendingPathComponent("\(folderName).md")
        }

        let frontmatter = newPostContent(
            sectionName: targetSection.name,
            format: format,
            slug: slug,
            date: date,
            siteURL: siteURL
        )

        if !shouldUseHugoCLI, let validationError = validateFrontmatterTemplate(frontmatter) {
            isLoading = false
            presentNewPostError(validationError)
            return
        }

        guard
            shouldUseHugoCLI
                || confirmFrontmatterPreview(
                    frontmatter: frontmatter,
                    sectionName: targetSection.name,
                    format: format
                )
        else {
            isLoading = false
            return
        }

        WorkspacePreferenceStore.setNewPostFormat(format, for: siteURL)
        let preferredSectionName = targetSection.name == "(root)" ? nil : targetSection.name
        WorkspacePreferenceStore.setPreferredSection(preferredSectionName, for: siteURL)

        Task(priority: .userInitiated) { [weak self] in
            do {
                let createdURL = try await Self.createNewPostFileInBackground(
                    contentCreator: contentCreator,
                    siteURL: siteURL,
                    config: config,
                    sectionName: targetSection.name,
                    sectionDir: sectionDir,
                    format: format,
                    folderName: folderName,
                    expectedFileURL: expectedFileURL,
                    useHugoCLI: shouldUseHugoCLI,
                    frontmatter: frontmatter
                )

                await MainActor.run {
                    guard let self else { return }
                    guard self.currentFolderURL?.standardizedFileURL == siteURL.standardizedFileURL else {
                        self.isLoading = false
                        return
                    }

                    self.loadContent(from: siteURL)
                    let finalURL = self.resolveCreatedURLAfterRefresh(
                        createdURL: createdURL, fallbackURL: expectedFileURL)
                    self.selectedFileURL = finalURL
                    self.onOpenFile?(finalURL)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.isLoading = false
                    self.presentHugoDiagnostics(for: error)
                }
            }
        }
    }

    // MARK: - Delete Content

    /// Moves the given content item to the system Trash.
    ///
    /// For bundle format, moves the entire folder. For file format,
    /// moves just the markdown file. Updates the sections list and clears
    /// the selected file if it was deleted.
    ///
    /// - Parameter item: The content item to delete.
    func deleteContent(_ item: ContentItem) {
        let fm = FileManager.default
        guard let contentDir = contentDirectoryURL else {
            lastError = .unsafeFileOperation(item.url.path)
            return
        }

        let targetURL: URL
        switch item.format {
        case .bundle:
            targetURL = item.url.deletingLastPathComponent()
        case .file:
            targetURL = item.url
        }

        let standardizedTarget = targetURL.standardizedFileURL
        guard PathSafety.isSameOrDescendant(standardizedTarget, of: contentDir.standardizedFileURL) else {
            lastError = .unsafeFileOperation(targetURL.path)
            return
        }

        do {
            try fm.trashItem(at: standardizedTarget, resultingItemURL: nil)

            let sectionName = item.section.isEmpty ? "(root)" : item.section
            if let sectionIdx = sections.firstIndex(where: { $0.name == sectionName }) {
                sections[sectionIdx].items.removeAll { $0.id == item.id }
            }

            if selectedFileURL == item.url {
                selectedFileURL = nil
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Hugo Validation

    private func validateHugoSite(at url: URL) -> Bool {
        let fm = FileManager.default

        let configFiles = [
            "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
            "config.toml", "config.yaml", "config.yml", "config.json",
        ]
        for file in configFiles {
            if fm.fileExists(atPath: url.appendingPathComponent(file).path) {
                return true
            }
        }

        var isDir: ObjCBool = false
        let configDir = url.appendingPathComponent("config")
        if fm.fileExists(atPath: configDir.path, isDirectory: &isDir), isDir.boolValue {
            return true
        }

        return false
    }

    /// Collects shortcode names from the site's (and its themes')
    /// layouts/shortcodes directories for the Insert Shortcode menu.
    private func discoverSiteShortcodes(siteURL: URL) {
        var directories = [siteURL.appendingPathComponent("layouts/shortcodes")]
        for theme in hugoConfig?.themes ?? [] {
            directories.append(
                siteURL
                    .appendingPathComponent("themes")
                    .appendingPathComponent(theme)
                    .appendingPathComponent("layouts/shortcodes")
            )
        }

        var names = Set<String>()
        for directory in directories {
            let entries =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
            for entry in entries where entry.pathExtension.lowercased() == "html" {
                names.insert(entry.deletingPathExtension().lastPathComponent)
            }
        }

        siteShortcodes = names.sorted()
    }

    // MARK: - Content Loading

    private func loadContent(from siteURL: URL) {
        isLoading = true
        hugoConfig = HugoConfig.load(from: siteURL)
        siteName = siteURL.lastPathComponent
        discoverSiteShortcodes(siteURL: siteURL)

        guard let config = hugoConfig else {
            sections = []
            isLoading = false
            return
        }

        let candidateContentDir = siteURL.appendingPathComponent(config.contentDir).standardizedFileURL
        guard PathSafety.isSameOrDescendant(candidateContentDir, of: siteURL) else {
            sections = []
            isLoading = false
            presentSafetyWarning(
                title: "Blocked unsafe contentDir path",
                detail: "Configured contentDir '\(config.contentDir)' escapes the workspace boundary and was ignored."
            )
            return
        }
        let contentDir = candidateContentDir

        let fm = FileManager.default
        guard fm.fileExists(atPath: contentDir.path) else {
            sections = []
            isLoading = false
            presentSafetyWarning(
                title: "Configured content directory not found",
                detail: "Configured contentDir '\(config.contentDir)' does not exist in this workspace."
            )
            return
        }

        let loadedSections = WorkspaceContentScanner.collectContentSections(from: contentDir)
        sections = loadedSections.sorted()
        configureContentWatchers(contentDir: contentDir)
        isLoading = false
    }

    private func preferredNewPostFormat() -> ContentFormat {
        if let workspaceFormat = WorkspacePreferenceStore.preferences(for: currentFolderURL).newPostFormat {
            return workspaceFormat
        }
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.newPostFormat) ?? ""
        return ContentFormat(rawValue: stored) ?? .bundle
    }

    private func resolveNewPostSection() -> ContentSection? {
        if let preferredName = WorkspacePreferenceStore.preferences(for: currentFolderURL).preferredSection,
            let preferred = sections.first(where: { $0.name == preferredName })
        {
            return preferred
        }

        let preferredNames = ["blog", "posts"]
        if let preferred = sections.first(where: { preferredNames.contains($0.name.lowercased()) }) {
            return preferred
        }

        let nonRoot = sections.filter { $0.name != "(root)" }
        if let first = nonRoot.first {
            return first
        }

        if let root = sections.first(where: { $0.name == "(root)" }) {
            return root
        }

        if let contentDir = contentDirectoryURL {
            return ContentSection(name: "(root)", url: contentDir, items: [])
        }

        return nil
    }

    private func newPostSectionCandidates() -> [ContentSection] {
        var candidates = sections.filter { $0.name != "(root)" }
        if let root = sections.first(where: { $0.name == "(root)" }) {
            candidates.append(root)
        }

        if candidates.isEmpty, let contentDir = contentDirectoryURL {
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: contentDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for entry in entries {
                    guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey]),
                        values.isDirectory == true
                    else {
                        continue
                    }
                    candidates.append(ContentSection(name: entry.lastPathComponent, url: entry, items: []))
                }
                candidates.sort()
            }

            if candidates.isEmpty {
                candidates.append(ContentSection(name: "(root)", url: contentDir, items: []))
            }
        }

        return candidates
    }

    private func pickSectionForNewPost(from candidates: [ContentSection]) -> ContentSection? {
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }

        // In tests/headless mode, skip UI and pick the current preferred section.
        guard NSApp != nil, !Self.isRunningTests else {
            return resolveNewPostSection() ?? candidates[0]
        }

        let alert = NSAlert()
        alert.messageText = "Choose section for new post"
        alert.informativeText = "Select where the new post should be created."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26), pullsDown: false)
        for section in candidates {
            popup.addItem(withTitle: sectionOptionTitle(section))
        }
        if let preferred = resolveNewPostSection(),
            let preferredIdx = candidates.firstIndex(where: { $0.name == preferred.name })
        {
            popup.selectItem(at: preferredIdx)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let selectedIdx = max(0, popup.indexOfSelectedItem)
        return candidates[selectedIdx]
    }

    private func sectionOptionTitle(_ section: ContentSection) -> String {
        section.name == "(root)" ? "Root" : section.displayName
    }

    private func newPostContent(
        sectionName: String,
        format: ContentFormat,
        slug: String,
        date: Date,
        siteURL: URL
    ) -> String {
        let config = hugoConfig ?? .default
        let builder = NewPostBuilder(siteURL: siteURL, config: config)
        return builder.buildContent(
            sectionName: sectionName,
            format: format,
            title: Self.defaultNewPostTitle,
            slug: slug,
            date: date
        )
    }

    private func validateFrontmatterTemplate(_ template: String) -> String? {
        guard detectFrontmatterBlock(in: template) != nil else {
            return "Template is missing a valid front matter block."
        }

        if FrontmatterParser.value(forKey: "title", in: template) == nil {
            return "Template front matter is missing a valid title."
        }

        if FrontmatterParser.date(forKey: "date", in: template) == nil {
            return "Template front matter is missing a valid date."
        }

        return nil
    }

    private func confirmFrontmatterPreview(
        frontmatter: String,
        sectionName: String,
        format: ContentFormat
    ) -> Bool {
        guard NSApp != nil, !Self.isRunningTests else { return true }

        let alert = NSAlert()
        alert.messageText = "Review front matter template"
        let target = sectionName == "(root)" ? "root content" : sectionName
        alert.informativeText = "Section: \(target) • Format: \(format.displayName)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        textView.string = frontmatter
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        alert.accessoryView = scrollView

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentNewPostError(_ message: String) {
        guard !Self.isRunningTests else {
            Self.logger.error("Cannot create new post: \(message)")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Cannot create new post"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentSafetyWarning(title: String, detail: String) {
        let fingerprint = "\(title)|\(detail)"
        guard fingerprint != lastSafetyWarning else { return }
        lastSafetyWarning = fingerprint

        guard NSApp != nil, !Self.isRunningTests else {
            Self.logger.error("\(title): \(detail)")
            return
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func presentHugoDiagnostics(for error: Error) {
        guard let hugoError = error as? HugoContentCreatorError else {
            NSApp.presentError(error)
            return
        }

        guard NSApp != nil, !Self.isRunningTests else {
            Self.logger.error("Hugo error: \(hugoError.debugDescription)")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Hugo command diagnostics"
        alert.informativeText = hugoError.errorDescription ?? "Hugo reported an unknown error."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        textView.string = hugoError.debugDescription
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        alert.accessoryView = scrollView
        alert.runModal()
    }

    private nonisolated static func createNewPostFileInBackground(
        contentCreator: any HugoContentCreator,
        siteURL: URL,
        config: HugoConfig,
        sectionName: String,
        sectionDir: URL,
        format: ContentFormat,
        folderName: String,
        expectedFileURL: URL,
        useHugoCLI: Bool,
        frontmatter: String
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let createdURL = try createNewPostFileSync(
                        contentCreator: contentCreator,
                        siteURL: siteURL,
                        config: config,
                        sectionName: sectionName,
                        sectionDir: sectionDir,
                        format: format,
                        folderName: folderName,
                        expectedFileURL: expectedFileURL,
                        useHugoCLI: useHugoCLI,
                        frontmatter: frontmatter
                    )
                    continuation.resume(returning: createdURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func createNewPostFileSync(
        contentCreator: any HugoContentCreator,
        siteURL: URL,
        config: HugoConfig,
        sectionName: String,
        sectionDir: URL,
        format: ContentFormat,
        folderName: String,
        expectedFileURL: URL,
        useHugoCLI: Bool,
        frontmatter: String
    ) throws -> URL {
        if useHugoCLI {
            let relativePath = Self.newPostRelativePath(
                sectionName: sectionName,
                format: format,
                folderName: folderName
            )
            let kind = sectionName == "(root)" ? nil : sectionName
            return try contentCreator.createNewContent(
                siteURL: siteURL,
                contentDir: config.contentDir,
                relativePath: relativePath,
                kind: kind
            )
        }

        if format == .bundle {
            let folderURL = sectionDir.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        try frontmatter.write(to: expectedFileURL, atomically: true, encoding: .utf8)
        return expectedFileURL
    }

    private nonisolated static func newPostRelativePath(
        sectionName: String,
        format: ContentFormat,
        folderName: String
    ) -> String {
        var components: [String] = []
        if sectionName != "(root)" {
            components.append(sectionName)
        }

        switch format {
        case .bundle:
            components.append(folderName)
            components.append("index.md")
        case .file:
            components.append("\(folderName).md")
        }

        return components.joined(separator: "/")
    }

    private func resolveCreatedURLAfterRefresh(createdURL: URL, fallbackURL: URL) -> URL {
        let createdPath = createdURL.standardizedFileURL.path
        if let item =
            sections
            .flatMap(\.items)
            .first(where: { $0.url.standardizedFileURL.path == createdPath })
        {
            return item.url
        }

        let fallbackPath = fallbackURL.standardizedFileURL.path
        if let item =
            sections
            .flatMap(\.items)
            .first(where: { $0.url.standardizedFileURL.path == fallbackPath })
        {
            return item.url
        }

        return createdURL
    }

    // MARK: - Private: Security-Scoped Bookmarks

    private func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            Self.logger.error("Failed to create bookmark for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func startAccessingFolder(_ url: URL) {
        adoptAccessedFolder(url, scopeActive: url.startAccessingSecurityScopedResource())
    }

    /// Takes ownership of a folder whose security scope (if any) has
    /// already been started by the caller.
    private func adoptAccessedFolder(_ url: URL, scopeActive: Bool) {
        securityScopedURL = scopeActive ? url : nil
        currentFolderURL = url
    }

    private func stopAccessingCurrentFolder() {
        stopWatchingContentChanges()
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func configureContentWatchers(contentDir: URL) {
        stopWatchingContentChanges()

        configureContentDirectoryWatcher(contentDir: contentDir)

        let watchedSections = sections.filter { $0.name != "(root)" }
        for section in watchedSections {
            configureSectionWatchers(sectionName: section.name, sectionURL: section.url, contentDir: contentDir)
        }
    }

    private func configureContentDirectoryWatcher(contentDir: URL) {
        let fd = open(contentDir.path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Failed to watch content directory: \(contentDir.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleContentReload()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()

        contentDirectoryWatcher = source
    }

    /// Watches a section directory and every nested directory beneath it.
    /// kqueue directory events only fire for direct children, so each level
    /// of nesting (content/blog/2024/...) needs its own watcher.
    private func configureSectionWatchers(sectionName: String, sectionURL: URL, contentDir: URL) {
        for directory in [sectionURL] + nestedDirectories(under: sectionURL, contentRoot: contentDir) {
            addSectionDirectoryWatcher(
                directory: directory,
                sectionName: sectionName,
                sectionURL: sectionURL,
                contentDir: contentDir
            )
        }
    }

    private func addSectionDirectoryWatcher(
        directory: URL,
        sectionName: String,
        sectionURL: URL,
        contentDir: URL
    ) {
        let key = directory.standardizedFileURL.path
        guard sectionWatchers[key] == nil else { return }

        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Failed to watch section directory: \(directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleSectionRefresh(sectionName: sectionName, sectionURL: sectionURL, contentDir: contentDir)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()

        sectionWatchers[key] = source
    }

    private func nestedDirectories(under sectionURL: URL, contentRoot: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: sectionURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        var directories: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true else { continue }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard PathSafety.isSameOrDescendant(resolved, of: contentRoot) else {
                enumerator.skipDescendants()
                continue
            }
            directories.append(url)
        }
        return directories
    }

    /// Drops and re-registers the watchers for one section's subtree so
    /// directories created or deleted since the last scan are covered.
    private func rebuildSectionWatchers(sectionName: String, sectionURL: URL, contentDir: URL) {
        removeSectionWatchers(under: sectionURL)
        configureSectionWatchers(sectionName: sectionName, sectionURL: sectionURL, contentDir: contentDir)
    }

    private func removeSectionWatchers(under sectionURL: URL) {
        let prefix = sectionURL.standardizedFileURL.path
        for (key, watcher) in sectionWatchers where key == prefix || key.hasPrefix(prefix + "/") {
            watcher.setEventHandler {}
            watcher.cancel()
            sectionWatchers.removeValue(forKey: key)
        }
    }

    private func scheduleContentReload() {
        contentWatcherReloadTask?.cancel()
        contentWatcherReloadTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: Timing.contentReloadDebounce) } catch { return }  // task cancelled
            guard let self, let url = self.currentFolderURL else { return }
            self.loadContent(from: url)
        }
    }

    private func scheduleSectionRefresh(sectionName: String, sectionURL: URL, contentDir: URL) {
        sectionRefreshTasks[sectionName]?.cancel()
        sectionRefreshTasks[sectionName] = Task { @MainActor [weak self] in
            defer { self?.sectionRefreshTasks.removeValue(forKey: sectionName) }
            do { try await Task.sleep(nanoseconds: Timing.sectionRefreshDebounce) } catch { return }  // task cancelled
            guard let self else { return }
            guard self.currentFolderURL != nil else { return }
            guard let currentContentDir = self.contentDirectoryURL else { return }
            guard currentContentDir.standardizedFileURL == contentDir.standardizedFileURL else { return }

            if !FileManager.default.fileExists(atPath: sectionURL.path) {
                self.sections.removeAll { $0.name == sectionName }
                self.removeSectionWatchers(under: sectionURL)
                return
            }

            let refreshedItems = WorkspaceContentScanner.collectSectionItems(
                in: sectionURL,
                sectionName: sectionName,
                contentRoot: contentDir
            )
            self.rebuildSectionWatchers(sectionName: sectionName, sectionURL: sectionURL, contentDir: contentDir)

            if let idx = self.sections.firstIndex(where: { $0.name == sectionName }) {
                self.sections[idx].items = refreshedItems
            } else {
                self.sections.append(ContentSection(name: sectionName, url: sectionURL, items: refreshedItems))
                self.sections.sort()
            }

            let refreshedRootItems = WorkspaceContentScanner.collectRootItems(from: contentDir)
            if let rootIdx = self.sections.firstIndex(where: { $0.name == "(root)" }) {
                if refreshedRootItems.isEmpty {
                    self.sections.remove(at: rootIdx)
                } else {
                    self.sections[rootIdx].items = refreshedRootItems
                }
            } else if !refreshedRootItems.isEmpty {
                self.sections.append(ContentSection(name: "(root)", url: contentDir, items: refreshedRootItems))
            }
        }
    }

    private func stopWatchingContentChanges() {
        contentWatcherReloadTask?.cancel()
        contentWatcherReloadTask = nil

        for task in sectionRefreshTasks.values {
            task.cancel()
        }
        sectionRefreshTasks.removeAll()

        if let watcher = contentDirectoryWatcher {
            watcher.setEventHandler {}
            watcher.cancel()
        }
        contentDirectoryWatcher = nil

        for (_, watcher) in sectionWatchers {
            watcher.setEventHandler {}
            watcher.cancel()
        }
        sectionWatchers.removeAll()
    }

    private func openFolderWithoutBookmark(_ url: URL) {
        currentFolderURL = url
        if validateHugoSite(at: url) {
            loadContent(from: url)
        } else {
            isLoading = false
            lastError = .notHugoSite
        }
    }

    // MARK: - Private: Persistence

    private func saveCurrentBookmark(_ data: Data) {
        UserDefaults.standard.set(data, forKey: DefaultsKey.workspaceBookmark)
    }

    private func restoreLastWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.workspaceBookmark) else { return }

        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            Self.logger.error("Failed to resolve session bookmark: \(error.localizedDescription)")
            UserDefaults.standard.removeObject(forKey: DefaultsKey.workspaceBookmark)
            return
        }

        // Start the security scope before validating: without it, sandboxed
        // builds fail every stat inside the folder, and deleting the
        // bookmark here would permanently break session restore. Keep the
        // bookmark on failure — it may be transient (unmounted volume).
        let scopeActive = url.startAccessingSecurityScopedResource()
        guard validateHugoSite(at: url) else {
            if scopeActive { url.stopAccessingSecurityScopedResource() }
            Self.logger.error("Saved workspace no longer looks like a Hugo site: \(url.path)")
            return
        }

        if isStale {
            if let newData = createBookmark(for: url) {
                saveCurrentBookmark(newData)
            }
        }

        adoptAccessedFolder(url, scopeActive: scopeActive)
        loadContent(from: url)
    }

    private func loadRecentWorkspaces() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.workspaceRecent) else {
            return
        }
        do {
            recentWorkspaces = try JSONDecoder().decode([WorkspaceRef].self, from: data)
        } catch {
            Self.logger.error("Failed to decode recent workspaces: \(error.localizedDescription)")
        }
    }

    private func saveRecentWorkspaces() {
        do {
            let data = try JSONEncoder().encode(recentWorkspaces)
            UserDefaults.standard.set(data, forKey: DefaultsKey.workspaceRecent)
        } catch {
            Self.logger.error("Failed to encode recent workspaces: \(error.localizedDescription)")
        }
    }

    private func addToRecent(url: URL, bookmarkData: Data) {
        let ref = WorkspaceRef(path: url.path, bookmarkData: bookmarkData)
        recentWorkspaces.removeAll { $0.path == ref.path }
        recentWorkspaces.insert(ref, at: 0)
        if recentWorkspaces.count > maxRecent {
            recentWorkspaces = Array(recentWorkspaces.prefix(maxRecent))
        }
        saveRecentWorkspaces()
    }

    private func removeFromRecent(_ ref: WorkspaceRef) {
        recentWorkspaces.removeAll { $0.path == ref.path }
        saveRecentWorkspaces()
    }

    /// Moves a reopened workspace to the front of the recents list, dropping
    /// the stored entry even when bookmark resolution yielded a moved path.
    private func promoteRecent(_ ref: WorkspaceRef, resolvedURL: URL, bookmarkData: Data) {
        recentWorkspaces.removeAll { $0.path == ref.path }
        addToRecent(url: resolvedURL, bookmarkData: bookmarkData)
    }
}
