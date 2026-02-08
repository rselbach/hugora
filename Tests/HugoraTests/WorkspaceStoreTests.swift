import Foundation
import Testing
@testable import Hugora

// ---------------------------------------------------------------------------
// WorkspaceStore tests
//
// These exercise the public surface of WorkspaceStore: site validation (via
// openFolder), content loading, post creation, and deletion.  Everything runs
// against throwaway temp directories so we never touch real Hugo sites.
//
// Community-themed test data because streets ahead.
// ---------------------------------------------------------------------------

@Suite("WorkspaceStore")
@MainActor
struct WorkspaceStoreTests {

    // UserDefaults keys the store reads/writes.
    private static let defaultsKeys = [
        "hugora.workspace.bookmark",
        "hugora.workspace.recent",
        "newPostFormat",
    ]

    /// Create a WorkspaceStore with a clean UserDefaults slate.
    /// Restores original values when the returned closure is called.
    private func makeStore() -> (store: WorkspaceStore, cleanup: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = Self.defaultsKeys.map { ($0, defaults.object(forKey: $0)) }

        // Clear keys so the init doesn't try to restore a stale workspace.
        for key in Self.defaultsKeys { defaults.removeObject(forKey: key) }

        let store = WorkspaceStore()

        let cleanup = {
            for (key, original) in saved {
                if let original { defaults.set(original, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        return (store, cleanup)
    }

    /// Create a minimal Hugo site structure in a temp directory.
    private func makeTempHugoSite(
        configFileName: String = "hugo.toml",
        configContent: String = """
            title = "Greendale Community College Blog"
            """,
        sections: [String] = ["posts"],
        posts: [(section: String, slug: String, content: String)] = []
    ) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugora-test-\(UUID().uuidString)")
        let fm = FileManager.default

        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        // Config file
        let configURL = base.appendingPathComponent(configFileName)
        try configContent.write(to: configURL, atomically: true, encoding: .utf8)

        // Content directory + sections
        let contentDir = base.appendingPathComponent("content")
        try fm.createDirectory(at: contentDir, withIntermediateDirectories: true)

        for section in sections {
            let sectionDir = contentDir.appendingPathComponent(section)
            try fm.createDirectory(at: sectionDir, withIntermediateDirectories: true)
        }

        // Posts
        for post in posts {
            let sectionDir = contentDir.appendingPathComponent(post.section)
            if !fm.fileExists(atPath: sectionDir.path) {
                try fm.createDirectory(at: sectionDir, withIntermediateDirectories: true)
            }
            let fileURL = sectionDir.appendingPathComponent("\(post.slug).md")
            try post.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return base
    }

    // MARK: - validateHugoSite (tested via openFolder)

    @Test("Accepts Hugo site with hugo.toml", arguments: [
        "hugo.toml", "hugo.yaml", "hugo.json",
        "config.toml", "config.yaml", "config.json",
    ])
    func acceptsValidConfigFile(configFile: String) throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(configFileName: configFile)
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.lastError == nil)
        #expect(store.currentFolderURL != nil)
    }

    @Test("Accepts Hugo site with config/ directory")
    func acceptsConfigDirectory() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugora-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // config/ directory (no individual config file)
        let configDir = base.appendingPathComponent("config")
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        store.openFolder(base)

        #expect(store.lastError == nil)
        #expect(store.currentFolderURL != nil)
    }

    @Test("Rejects directory without Hugo config")
    func rejectsNonHugoDirectory() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("hugora-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        store.openFolder(emptyDir)

        #expect(store.lastError == .notHugoSite)
        #expect(store.currentFolderURL == nil)
    }

    // MARK: - loadContent (tested via openFolder)

    @Test("Loads sections and items from content directory")
    func loadsSectionsAndItems() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(
            sections: ["posts", "pages"],
            posts: [
                (section: "posts", slug: "2024-01-15-troy-barnes-adventure", content: """
                ---
                title: "Troy Barnes's Big Adventure"
                date: 2024-01-15
                ---
                Troy and Abed in the morning!
                """),
                (section: "posts", slug: "2024-03-01-paintball-war", content: """
                ---
                title: "The Paintball War"
                date: 2024-03-01
                ---
                It's like the Hunger Games but with paint.
                """),
                (section: "pages", slug: "about", content: """
                ---
                title: "About Greendale"
                ---
                E Pluribus Anus.
                """),
            ]
        )
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.lastError == nil)
        #expect(store.sections.count >= 2)

        let postsSection = store.sections.first { $0.name == "posts" }
        #expect(postsSection != nil)
        #expect(postsSection?.items.count == 2)

        let pagesSection = store.sections.first { $0.name == "pages" }
        #expect(pagesSection != nil)
        #expect(pagesSection?.items.count == 1)
    }

    @Test("Loads bundle-format posts (index.md inside folder)")
    func loadsBundlePosts() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let base = try makeTempHugoSite(sections: ["blog"])
        defer { try? FileManager.default.removeItem(at: base) }

        // Create a bundle post: content/blog/senor-chang/index.md
        let bundleDir = base
            .appendingPathComponent("content/blog/senor-chang")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let indexMD = bundleDir.appendingPathComponent("index.md")
        try """
        ---
        title: "Senor Chang's Reign of Terror"
        date: 2024-06-01
        ---
        I am a Spanish genius!
        """.write(to: indexMD, atomically: true, encoding: .utf8)

        store.openFolder(base)

        let blogSection = store.sections.first { $0.name == "blog" }
        #expect(blogSection != nil)
        #expect(blogSection?.items.count == 1)

        let item = blogSection?.items.first
        #expect(item?.format == .bundle)
        #expect(item?.slug == "senor-chang")
    }

    @Test("Empty content directory yields no sections")
    func emptyContentDirYieldsNoSections() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: [])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.lastError == nil)
        #expect(store.sections.isEmpty)
    }

    @Test("Site name is set from directory name")
    func siteNameFromDirectory() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite()
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.siteName == siteURL.lastPathComponent)
    }

    @Test("Hugo config title is loaded")
    func hugoConfigTitleLoaded() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(
            configContent: """
            title = "Human Beings Unite"
            """
        )
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.hugoConfig?.title == "Human Beings Unite")
    }

    @Test("Root-level markdown files appear in (root) section")
    func rootLevelMarkdownFiles() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: [])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        // Add a root-level .md file
        let aboutFile = siteURL
            .appendingPathComponent("content/about.md")
        try """
        ---
        title: "About the Study Group"
        ---
        We are Greendale students.
        """.write(to: aboutFile, atomically: true, encoding: .utf8)

        store.openFolder(siteURL)

        let rootSection = store.sections.first { $0.name == "(root)" }
        #expect(rootSection != nil)
        #expect(rootSection?.items.count == 1)
    }

    @Test("_index.md at root content level is excluded")
    func indexMdExcludedFromRoot() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: [])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        let indexFile = siteURL.appendingPathComponent("content/_index.md")
        try """
        ---
        title: "Home"
        ---
        Welcome to Greendale.
        """.write(to: indexFile, atomically: true, encoding: .utf8)

        store.openFolder(siteURL)

        // _index.md should be excluded, so no root section
        let rootSection = store.sections.first { $0.name == "(root)" }
        #expect(rootSection == nil)
    }

    // MARK: - createNewPost

    @Test("Creates a new post in the preferred section")
    func createsNewPost() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: ["posts"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)
        #expect(store.lastError == nil)

        // posts is a preferred section name, so createNewPost should target it
        let sectionBefore = store.sections.first { $0.name == "posts" }
        let countBefore = sectionBefore?.items.count ?? 0

        store.createNewPost()

        let sectionAfter = store.sections.first { $0.name == "posts" }
        #expect(sectionAfter != nil)
        #expect((sectionAfter?.items.count ?? 0) == countBefore + 1)

        // The new post file should exist on disk
        if let newItem = sectionAfter?.items.first {
            #expect(FileManager.default.fileExists(atPath: newItem.url.path))

            // Verify it contains frontmatter with a title
            let content = try String(contentsOf: newItem.url, encoding: .utf8)
            #expect(content.contains("title:"))
            #expect(content.contains("date:"))
        }
    }

    @Test("New post uses bundle format by default")
    func newPostBundleFormatDefault() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        // Make sure newPostFormat isn't set (default = bundle)
        UserDefaults.standard.removeObject(forKey: "newPostFormat")

        let siteURL = try makeTempHugoSite(sections: ["blog"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)
        store.createNewPost()

        let blogSection = store.sections.first { $0.name == "blog" }
        let newItem = blogSection?.items.first
        #expect(newItem?.format == .bundle)
        if let url = newItem?.url {
            #expect(url.lastPathComponent == "index.md")
        }
    }

    @Test("New post uses file format when preference set")
    func newPostFileFormat() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        UserDefaults.standard.set("file", forKey: "newPostFormat")

        let siteURL = try makeTempHugoSite(sections: ["blog"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)
        store.createNewPost()

        let blogSection = store.sections.first { $0.name == "blog" }
        let newItem = blogSection?.items.first
        #expect(newItem?.format == .file)
        if let url = newItem?.url {
            #expect(url.pathExtension == "md")
            #expect(url.lastPathComponent != "index.md")
        }
    }

    @Test("Creating multiple posts increments slug suffix")
    func multiplePostsIncrementSlug() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: ["posts"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        store.createNewPost()
        store.createNewPost()

        let section = store.sections.first { $0.name == "posts" }
        #expect((section?.items.count ?? 0) == 2)

        // Both items should have different URLs
        if let items = section?.items, items.count == 2 {
            #expect(items[0].url != items[1].url)
        }
    }

    @Test("Selected file is set after creating new post")
    func selectedFileSetAfterCreate() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: ["posts"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        #expect(store.selectedFileURL == nil)
        store.createNewPost()
        #expect(store.selectedFileURL != nil)
    }

    // MARK: - deleteContent

    @Test("Deleting a file-format item removes it from sections")
    func deleteFileItem() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(
            sections: ["posts"],
            posts: [
                (section: "posts", slug: "2024-01-01-abed-nadir-film", content: """
                ---
                title: "Abed Nadir's Student Film"
                date: 2024-01-01
                ---
                Cool. Cool cool cool.
                """),
            ]
        )
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        let section = store.sections.first { $0.name == "posts" }
        #expect(section?.items.count == 1)

        guard let item = section?.items.first else {
            #expect(Bool(false), "Expected an item to delete")
            return
        }

        store.deleteContent(item)

        let sectionAfter = store.sections.first { $0.name == "posts" }
        #expect(sectionAfter?.items.first { $0.id == item.id } == nil)

        // File should no longer exist at original path (moved to trash)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
    }

    @Test("Deleting selected item clears selectedFileURL")
    func deleteSelectedItemClearsSelection() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(
            sections: ["posts"],
            posts: [
                (section: "posts", slug: "2024-02-14-jeff-winger-speech", content: """
                ---
                title: "Jeff Winger's Valentines Day Speech"
                date: 2024-02-14
                ---
                I discovered at a very early age that if I talk long enough,
                I can make anything right or wrong.
                """),
            ]
        )
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)

        guard let item = store.sections.first(where: { $0.name == "posts" })?.items.first else {
            #expect(Bool(false), "Expected a post item")
            return
        }

        store.openFile(item.url)
        #expect(store.selectedFileURL == item.url)

        store.deleteContent(item)
        #expect(store.selectedFileURL == nil)
    }

    @Test("Deleting a bundle-format item removes the parent folder")
    func deleteBundleItem() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: ["blog"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        let bundleDir = siteURL.appendingPathComponent("content/blog/dean-pelton-outfit")
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        let indexMD = bundleDir.appendingPathComponent("index.md")
        try """
        ---
        title: "Dean Pelton's Outfit of the Day"
        date: 2024-04-01
        ---
        This is a peanut bar, and I am a peanut bar.
        """.write(to: indexMD, atomically: true, encoding: .utf8)

        store.openFolder(siteURL)

        guard let item = store.sections.first(where: { $0.name == "blog" })?.items.first else {
            #expect(Bool(false), "Expected a bundle item")
            return
        }
        #expect(item.format == .bundle)

        store.deleteContent(item)

        // The bundle folder itself should be gone
        #expect(!FileManager.default.fileExists(atPath: bundleDir.path))
    }

    // MARK: - closeWorkspace

    @Test("Close workspace resets all state")
    func closeWorkspaceResetsState() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(
            sections: ["posts"],
            posts: [
                (section: "posts", slug: "anything", content: """
                ---
                title: "Pierce Hawthorne's Moist Towelettes"
                ---
                Streets ahead.
                """),
            ]
        )
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)
        #expect(store.currentFolderURL != nil)
        #expect(!store.sections.isEmpty)

        store.closeWorkspace()

        #expect(store.currentFolderURL == nil)
        #expect(store.sections.isEmpty)
        #expect(store.hugoConfig == nil)
        #expect(store.siteName == nil)
        #expect(store.lastError == nil)
    }

    // MARK: - refreshPosts

    @Test("Refresh reloads content from disk")
    func refreshReloadsContent() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let siteURL = try makeTempHugoSite(sections: ["posts"])
        defer { try? FileManager.default.removeItem(at: siteURL) }

        store.openFolder(siteURL)
        #expect(store.sections.first(where: { $0.name == "posts" })?.items.isEmpty == true)

        // Add a file on disk after initial load
        let newFile = siteURL.appendingPathComponent("content/posts/britta-perry.md")
        try """
        ---
        title: "Britta Perry's Activism Blog"
        date: 2024-09-01
        ---
        I lived in New York!
        """.write(to: newFile, atomically: true, encoding: .utf8)

        store.refreshPosts()

        let section = store.sections.first { $0.name == "posts" }
        #expect(section?.items.count == 1)
    }

    // MARK: - openFile

    @Test("openFile sets selectedFileURL")
    func openFileSetsSelected() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let url = URL(fileURLWithPath: "/tmp/test-file.md")
        store.openFile(url)

        #expect(store.selectedFileURL == url)
    }
}
