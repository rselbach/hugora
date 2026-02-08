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

enum WorkspaceError: LocalizedError {
    case notHugoSite

    var errorDescription: String? {
        switch self {
        case .notHugoSite:
            "This folder doesn't appear to be a Hugo site. Expected hugo.toml, config.toml, or a config/ directory."
        }
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "WorkspaceStore"
    )

    @Published private(set) var sections: [ContentSection] = []
    @Published private(set) var hugoConfig: HugoConfig?
    @Published private(set) var currentFolderURL: URL?
    @Published private(set) var siteName: String?
    @Published var recentWorkspaces: [WorkspaceRef] = []
    @Published var lastError: WorkspaceError?
    
    /// Which file is highlighted in the sidebar list (not an event — just selection state)
    @Published var selectedFileURL: URL?

    /// Called when a file should be opened in the editor.
    /// Wired up by ContentView so WorkspaceStore doesn't need to know about EditorState.
    var onOpenFile: ((URL) -> Void)?

    private var securityScopedURL: URL?
    private let hugoContentCreator: any HugoContentCreator
    private static let newPostDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let maxRecent = 10

    var contentDirectoryURL: URL? {
        guard let folder = currentFolderURL, let config = hugoConfig else { return nil }
        let candidate = folder.appendingPathComponent(config.contentDir).standardizedFileURL
        guard candidate.path.hasPrefix(folder.standardizedFileURL.path) else { return nil }
        return candidate
    }

    init(hugoContentCreator: any HugoContentCreator = HugoCLIContentCreator()) {
        self.hugoContentCreator = hugoContentCreator
        loadRecentWorkspaces()
        restoreLastWorkspace()
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Open Folder

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Hugo site folder"
        panel.prompt = "Open"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openFolder(url)
        }
    }

    func openFolder(_ url: URL) {
        stopAccessingCurrentFolder()
        lastError = nil

        guard validateHugoSite(at: url) else {
            lastError = .notHugoSite
            return
        }

        guard let bookmarkData = createBookmark(for: url) else {
            openFolderWithoutBookmark(url)
            return
        }

        saveCurrentBookmark(bookmarkData)
        addToRecent(url: url, bookmarkData: bookmarkData)
        startAccessingFolder(url)
        loadContent(from: url)
    }

    func openRecent(_ ref: WorkspaceRef) {
        stopAccessingCurrentFolder()
        lastError = nil

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
            Self.logger.error("Failed to resolve bookmark for recent workspace \(ref.path): \(error.localizedDescription)")
            removeFromRecent(ref)
            return
        }

        guard validateHugoSite(at: url) else {
            removeFromRecent(ref)
            lastError = .notHugoSite
            return
        }

        guard isStale else {
            saveCurrentBookmark(ref.bookmarkData)
            startAccessingFolder(url)
            loadContent(from: url)
            return
        }

        if let newData = createBookmark(for: url) {
            let updatedRef = WorkspaceRef(path: url.path, bookmarkData: newData)
            updateRecent(updatedRef)
            saveCurrentBookmark(newData)
        }

        startAccessingFolder(url)
        loadContent(from: url)
    }

    func closeWorkspace() {
        stopAccessingCurrentFolder()
        sections = []
        hugoConfig = nil
        currentFolderURL = nil
        siteName = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.workspaceBookmark)
    }

    func refreshPosts() {
        guard let url = currentFolderURL else { return }
        loadContent(from: url)
    }

    // MARK: - Open File

    func openFile(_ url: URL) {
        selectedFileURL = url
        onOpenFile?(url)
    }

    // MARK: - Create New Post

    func createNewPost() {
        guard let siteURL = currentFolderURL else {
            presentNewPostError("No Hugo site is open.")
            return
        }

        guard let targetSection = resolveNewPostSection() else {
            presentNewPostError("No content section found. Add a section folder under your Hugo content directory.")
            return
        }

        let format = preferredNewPostFormat()
        let sectionDir = targetSection.url
        let config = hugoConfig ?? .default

        let date = Date()
        let datePrefix = Self.newPostDateFormatter.string(from: date)

        let baseSlug = "new-post"
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

        do {
            let createdURL = try createNewPostFile(
                siteURL: siteURL,
                config: config,
                sectionName: targetSection.name,
                sectionDir: sectionDir,
                format: format,
                folderName: folderName,
                expectedFileURL: expectedFileURL,
                date: date,
                slug: slug
            )
            loadContent(from: siteURL)
            let finalURL = resolveCreatedURLAfterRefresh(createdURL: createdURL, fallbackURL: expectedFileURL)
            selectedFileURL = finalURL
            onOpenFile?(finalURL)
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Delete Content

    func deleteContent(_ item: ContentItem) {
        let fm = FileManager.default

        do {
            switch item.format {
            case .bundle:
                let folderURL = item.url.deletingLastPathComponent()
                try fm.trashItem(at: folderURL, resultingItemURL: nil)
            case .file:
                try fm.trashItem(at: item.url, resultingItemURL: nil)
            }

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
            "hugo.toml", "hugo.yaml", "hugo.json",
            "config.toml", "config.yaml", "config.json"
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

    // MARK: - Content Loading

    private func loadContent(from siteURL: URL) {
        hugoConfig = HugoConfig.load(from: siteURL)
        siteName = siteURL.lastPathComponent

        guard let contentDir = contentDirectoryURL else {
            sections = []
            return
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: contentDir.path) else {
            sections = []
            return
        }

        let sectionDirs = listDirectoryEntries(at: contentDir)
        var loadedSections: [ContentSection] = []
        var rootItems: [ContentItem] = []

        for itemURL in sectionDirs {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                Self.logger.error("Failed to read resource values for \(itemURL.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            guard let isDir = resourceValues.isDirectory else {
                continue
            }

            if isDir {
                let sectionName = itemURL.lastPathComponent
                let items = collectItemsRecursively(in: itemURL, sectionName: sectionName).sorted()
                let section = ContentSection(name: sectionName, url: itemURL, items: items)
                loadedSections.append(section)
            } else if ContentFile.isSupportedContentFile(itemURL) {
                rootItems.append(ContentItem(url: itemURL, format: .file, section: "(root)"))
            }
        }

        if !rootItems.isEmpty {
            let rootSection = ContentSection(name: "(root)", url: contentDir, items: rootItems.sorted())
            loadedSections.append(rootSection)
        }

        sections = loadedSections.sorted()
    }

    private func preferredNewPostFormat() -> ContentFormat {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.newPostFormat) ?? ""
        return ContentFormat(rawValue: stored) ?? .bundle
    }

    private func resolveNewPostSection() -> ContentSection? {
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
            title: "New Post",
            slug: slug,
            date: date
        )
    }

    private func presentNewPostError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot create new post"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func createNewPostFile(
        siteURL: URL,
        config: HugoConfig,
        sectionName: String,
        sectionDir: URL,
        format: ContentFormat,
        folderName: String,
        expectedFileURL: URL,
        date: Date,
        slug: String
    ) throws -> URL {
        if hugoContentCreator.isAvailable(at: siteURL) {
            let relativePath = newPostRelativePath(
                sectionName: sectionName,
                format: format,
                folderName: folderName
            )
            let kind = sectionName == "(root)" ? nil : sectionName
            return try hugoContentCreator.createNewContent(
                siteURL: siteURL,
                contentDir: config.contentDir,
                relativePath: relativePath,
                kind: kind
            )
        }

        let frontmatter = newPostContent(
            sectionName: sectionName,
            format: format,
            slug: slug,
            date: date,
            siteURL: siteURL
        )

        if format == .bundle {
            let folderURL = sectionDir.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }

        try frontmatter.write(to: expectedFileURL, atomically: true, encoding: .utf8)
        return expectedFileURL
    }

    private func newPostRelativePath(
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
        if let item = sections
            .flatMap(\.items)
            .first(where: { $0.url.standardizedFileURL.path == createdPath }) {
            return item.url
        }

        let fallbackPath = fallbackURL.standardizedFileURL.path
        if let item = sections
            .flatMap(\.items)
            .first(where: { $0.url.standardizedFileURL.path == fallbackPath }) {
            return item.url
        }

        return createdURL
    }

    private func collectItemsRecursively(in directoryURL: URL, sectionName: String) -> [ContentItem] {
        let entries = listDirectoryEntries(at: directoryURL)

        if let leafIndex = preferredLeafBundleIndex(in: entries) {
            // Leaf bundle: index.* is the page, descendants are page resources.
            return [ContentItem(url: leafIndex, format: .bundle, section: sectionName)]
        }

        var items: [ContentItem] = []
        for entry in entries {
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            } catch {
                Self.logger.error("Failed to read resource values for \(entry.lastPathComponent): \(error.localizedDescription)")
                continue
            }

            guard let isDirectory = values.isDirectory else { continue }

            if isDirectory {
                items.append(contentsOf: collectItemsRecursively(in: entry, sectionName: sectionName))
                continue
            }

            guard ContentFile.isSupportedContentFile(entry) else { continue }
            items.append(ContentItem(url: entry, format: .file, section: sectionName))
        }

        return items
    }

    private func preferredLeafBundleIndex(in entries: [URL]) -> URL? {
        entries.first { entry in
            ContentFile.isSupportedContentFile(entry) && ContentFile.isLeafBundleIndex(entry)
        }
    }

    private func listDirectoryEntries(at url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.error("Failed to list directory \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }
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
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
        currentFolderURL = url
    }

    private func stopAccessingCurrentFolder() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private func openFolderWithoutBookmark(_ url: URL) {
        currentFolderURL = url
        if validateHugoSite(at: url) {
            loadContent(from: url)
        } else {
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

        guard validateHugoSite(at: url) else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.workspaceBookmark)
            return
        }

        if isStale {
            if let newData = createBookmark(for: url) {
                saveCurrentBookmark(newData)
            }
        }

        startAccessingFolder(url)
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

    private func updateRecent(_ ref: WorkspaceRef) {
        if let idx = recentWorkspaces.firstIndex(where: { $0.path == ref.path }) {
            recentWorkspaces[idx] = ref
            saveRecentWorkspaces()
        }
    }
}
