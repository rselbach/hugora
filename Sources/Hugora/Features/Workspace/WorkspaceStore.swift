import Foundation
import AppKit
import Combine

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

final class WorkspaceStore: ObservableObject {
    @Published private(set) var sections: [ContentSection] = []
    @Published private(set) var hugoConfig: HugoConfig?
    @Published private(set) var currentFolderURL: URL?
    @Published private(set) var siteName: String?
    @Published var recentWorkspaces: [WorkspaceRef] = []
    @Published var lastError: WorkspaceError?
    
    /// File selected from sidebar to open in current editor
    @Published var selectedFileURL: URL?

    private var securityScopedURL: URL?
    private let bookmarkKey = "hugora.workspace.bookmark"
    private let recentKey = "hugora.workspace.recent"
    private let maxRecent = 10

    var contentDirectoryURL: URL? {
        guard let folder = currentFolderURL, let config = hugoConfig else { return nil }
        return folder.appendingPathComponent(config.contentDir)
    }

    init() {
        loadRecentWorkspaces()
        restoreLastWorkspace()
    }

    deinit {
        stopAccessingCurrentFolder()
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
        guard let url = try? URL(
            resolvingBookmarkData: ref.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
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
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    func refreshPosts() {
        guard let url = currentFolderURL else { return }
        loadContent(from: url)
    }

    // MARK: - Open File

    func openFile(_ url: URL) {
        selectedFileURL = url
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

        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = formatter.string(from: date)

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
        let fileURL: URL
        switch format {
        case .bundle:
            fileURL = folderURL.appendingPathComponent("index.md")
        case .file:
            fileURL = sectionDir.appendingPathComponent("\(folderName).md")
        }

        let frontmatter = newPostContent(
            sectionName: targetSection.name,
            format: format,
            slug: slug,
            date: date,
            siteURL: siteURL
        )

        do {
            if format == .bundle {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            try frontmatter.write(to: fileURL, atomically: true, encoding: .utf8)

            let newItem = ContentItem(url: fileURL, format: format, section: targetSection.name)
            if let idx = sections.firstIndex(where: { $0.name == targetSection.name }) {
                sections[idx].items.insert(newItem, at: 0)
                sections[idx].items.sort()
            } else {
                let newSection = ContentSection(name: targetSection.name, url: targetSection.url, items: [newItem])
                sections.append(newSection)
                sections.sort()
            }

            selectedFileURL = fileURL
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

        let sectionDirs = (try? fm.contentsOfDirectory(
            at: contentDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loadedSections: [ContentSection] = []

        // Collect root-level .md files as "Root Pages"
        var rootItems: [ContentItem] = []

        for itemURL in sectionDirs {
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = resourceValues.isDirectory else {
                continue
            }

            if isDir {
                // It's a section directory
                let sectionName = itemURL.lastPathComponent
                let items = loadItems(in: itemURL, sectionName: sectionName)
                let section = ContentSection(name: sectionName, url: itemURL, items: items.sorted())
                loadedSections.append(section)
            } else if itemURL.pathExtension.lowercased() == "md" {
                // Root-level markdown file (e.g., about.md)
                let fileName = itemURL.lastPathComponent
                if fileName != "_index.md" {
                    rootItems.append(ContentItem(url: itemURL, format: .file, section: "(root)"))
                }
            }
        }

        // Add root pages as a special section if any exist
        if !rootItems.isEmpty {
            let rootSection = ContentSection(name: "(root)", url: contentDir, items: rootItems.sorted())
            loadedSections.append(rootSection)
        }

        sections = loadedSections.sorted()
    }

    private func preferredNewPostFormat() -> ContentFormat {
        let stored = UserDefaults.standard.string(forKey: "newPostFormat") ?? ""
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

    private func loadItems(in sectionURL: URL, sectionName: String) -> [ContentItem] {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: sectionURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var items: [ContentItem] = []

        for itemURL in contents {
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = resourceValues.isDirectory else {
                continue
            }

            if isDir {
                let indexURL = itemURL.appendingPathComponent("index.md")
                if fm.fileExists(atPath: indexURL.path) {
                    items.append(ContentItem(url: indexURL, format: .bundle, section: sectionName))
                }
            } else if itemURL.pathExtension.lowercased() == "md" {
                items.append(ContentItem(url: itemURL, format: .file, section: sectionName))
            }
        }

        return items
    }

    // MARK: - Private: Security-Scoped Bookmarks

    private func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func restoreLastWorkspace() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }

        guard validateHugoSite(at: url) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
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
        guard let data = UserDefaults.standard.data(forKey: recentKey),
              let refs = try? JSONDecoder().decode([WorkspaceRef].self, from: data) else {
            return
        }
        recentWorkspaces = refs
    }

    private func saveRecentWorkspaces() {
        guard let data = try? JSONEncoder().encode(recentWorkspaces) else { return }
        UserDefaults.standard.set(data, forKey: recentKey)
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
