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

        if isStale {
            if let newData = createBookmark(for: url) {
                let updatedRef = WorkspaceRef(path: url.path, bookmarkData: newData)
                updateRecent(updatedRef)
                saveCurrentBookmark(newData)
            }
        } else {
            saveCurrentBookmark(ref.bookmarkData)
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
        guard let blogSection = sections.first(where: { 
            $0.name.lowercased() == "blog" || $0.name.lowercased() == "posts" 
        }) else { return }

        let blogDir = blogSection.url

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = formatter.string(from: Date())

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let isoDate = isoFormatter.string(from: Date())

        let baseSlug = "new-post"
        var slug = baseSlug
        var counter = 1

        while FileManager.default.fileExists(atPath: blogDir.appendingPathComponent("\(datePrefix)-\(slug)").path) ||
              FileManager.default.fileExists(atPath: blogDir.appendingPathComponent("\(datePrefix)-\(slug).md").path) {
            slug = "\(baseSlug)-\(counter)"
            counter += 1
        }

        let folderName = "\(datePrefix)-\(slug)"
        let folderURL = blogDir.appendingPathComponent(folderName)
        let fileURL = folderURL.appendingPathComponent("index.md")

        let frontmatter = """
            ---
            title: "New Post"
            date: \(isoDate)
            draft: true
            ---

            """

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try frontmatter.write(to: fileURL, atomically: true, encoding: .utf8)

            let newItem = ContentItem(url: fileURL, format: .bundle, section: blogSection.name)
            if let idx = sections.firstIndex(where: { $0.name == blogSection.name }) {
                sections[idx].items.insert(newItem, at: 0)
                sections[idx].items.sort()
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

            if let sectionIdx = sections.firstIndex(where: { $0.name == item.section }) {
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
                    rootItems.append(ContentItem(url: itemURL, format: .file, section: ""))
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
