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
    case noBlogDirectory

    var errorDescription: String? {
        switch self {
        case .notHugoSite:
            "This folder doesn't appear to be a Hugo site (no hugo.toml found)."
        case .noBlogDirectory:
            "No content/blog directory found in this Hugo site."
        }
    }
}

final class WorkspaceStore: ObservableObject {
    @Published private(set) var posts: [BlogPost] = []
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

    var blogDirectoryURL: URL? {
        currentFolderURL?.appendingPathComponent("content/blog")
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

        guard let bookmarkData = createBookmark(for: url) else {
            openFolderWithoutBookmark(url)
            return
        }

        saveCurrentBookmark(bookmarkData)
        addToRecent(url: url, bookmarkData: bookmarkData)
        startAccessingFolder(url)

        if !validateHugoSite(at: url) {
            lastError = .notHugoSite
            return
        }

        loadPosts(from: url)
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

        if !validateHugoSite(at: url) {
            lastError = .notHugoSite
            return
        }

        loadPosts(from: url)
    }

    func closeWorkspace() {
        stopAccessingCurrentFolder()
        posts = []
        currentFolderURL = nil
        siteName = nil
        lastError = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    func refreshPosts() {
        guard let url = currentFolderURL else { return }
        loadPosts(from: url)
    }

    // MARK: - Open File

    func openFile(_ url: URL) {
        selectedFileURL = url
    }

    // MARK: - Create New Post

    func createNewPost() {
        guard let blogDir = blogDirectoryURL else { return }

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

            let newPost = BlogPost(url: fileURL, format: .bundle)
            posts.insert(newPost, at: 0)
            posts.sort()

            selectedFileURL = fileURL
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Delete Post

    func deletePost(_ post: BlogPost) {
        let fm = FileManager.default

        do {
            switch post.format {
            case .bundle:
                let folderURL = post.url.deletingLastPathComponent()
                try fm.trashItem(at: folderURL, resultingItemURL: nil)
            case .file:
                try fm.trashItem(at: post.url, resultingItemURL: nil)
            }

            posts.removeAll { $0.id == post.id }

            if selectedFileURL == post.url {
                selectedFileURL = nil
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Hugo Validation

    private func validateHugoSite(at url: URL) -> Bool {
        let hugoConfigURL = url.appendingPathComponent("hugo.toml")
        return FileManager.default.fileExists(atPath: hugoConfigURL.path)
    }

    // MARK: - Post Loading

    private func loadPosts(from siteURL: URL) {
        let blogDir = siteURL.appendingPathComponent("content/blog")

        guard FileManager.default.fileExists(atPath: blogDir.path) else {
            lastError = .noBlogDirectory
            posts = []
            return
        }

        siteName = siteURL.lastPathComponent

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: blogDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var loadedPosts: [BlogPost] = []

        for itemURL in contents {
            guard let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = resourceValues.isDirectory else {
                continue
            }

            if isDir {
                // Bundle format: look for index.md
                let indexURL = itemURL.appendingPathComponent("index.md")
                if FileManager.default.fileExists(atPath: indexURL.path) {
                    loadedPosts.append(BlogPost(url: indexURL, format: .bundle))
                }
            } else if itemURL.pathExtension.lowercased() == "md" {
                // File format: direct .md file
                loadedPosts.append(BlogPost(url: itemURL, format: .file))
            }
        }

        posts = loadedPosts.sorted()
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
            loadPosts(from: url)
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
        ) else { return }

        if isStale {
            if let newData = createBookmark(for: url) {
                saveCurrentBookmark(newData)
            }
        }

        startAccessingFolder(url)

        if validateHugoSite(at: url) {
            loadPosts(from: url)
        }
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
