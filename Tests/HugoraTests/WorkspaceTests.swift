import Testing
import Foundation
@testable import Hugora

@Suite("ContentItem Tests")
struct ContentItemTests {
    @Test("Bundle format extracts slug from parent directory")
    func bundleSlugFromParent() {
        let url = URL(fileURLWithPath: "/site/content/blog/my-cool-post/index.md")
        let item = ContentItem(url: url, format: .bundle, section: "blog")

        #expect(item.slug == "my-cool-post")
        #expect(item.format == .bundle)
        #expect(item.section == "blog")
    }

    @Test("File format extracts slug from filename")
    func fileSlugFromFilename() {
        let url = URL(fileURLWithPath: "/site/content/blog/another-post.md")
        let item = ContentItem(url: url, format: .file, section: "blog")

        #expect(item.slug == "another-post")
        #expect(item.format == .file)
    }

    @Test("Title falls back to slug when no frontmatter")
    func titleFallsBackToSlug() {
        let url = URL(fileURLWithPath: "/nonexistent/post-slug.md")
        let item = ContentItem(url: url, format: .file, section: "blog")

        #expect(item.title == "post-slug")
    }

    @Test("Items with dates sort newest first")
    func itemsWithDatesSortNewestFirst() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldFile = tempDir.appendingPathComponent("old-post.md")
        try """
        ---
        title: "Old Post"
        date: 2023-01-15
        ---
        Old content
        """.write(to: oldFile, atomically: true, encoding: .utf8)

        let newFile = tempDir.appendingPathComponent("new-post.md")
        try """
        ---
        title: "New Post"
        date: 2024-06-20
        ---
        New content
        """.write(to: newFile, atomically: true, encoding: .utf8)

        let old = ContentItem(url: oldFile, format: .file, section: "blog")
        let new = ContentItem(url: newFile, format: .file, section: "blog")

        #expect(new < old)  // newer sorts first
    }

    @Test("Items without dates sort alphabetically")
    func itemsWithoutDatesSortAlphabetically() {
        let aItem = ContentItem(url: URL(fileURLWithPath: "/site/content/blog/aardvark.md"), format: .file, section: "blog")
        let zItem = ContentItem(url: URL(fileURLWithPath: "/site/content/blog/zebra.md"), format: .file, section: "blog")

        #expect(aItem < zItem)
    }

    @Test("Title extracted from frontmatter with quotes")
    func titleExtractedFromFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.md")
        try """
        ---
        title: "Greendale Community College Rules"
        date: 2024-01-01
        ---
        # Content here
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.title == "Greendale Community College Rules")
    }

    @Test("Title extracted from TOML frontmatter")
    func titleExtractedFromTomlFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.md")
        try """
        +++
        title = "Annie's Boobs"
        date = 2024-01-01
        +++
        # Content here
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.title == "Annie's Boobs")
    }

    @Test("Title extracted from frontmatter without quotes")
    func titleExtractedWithoutQuotes() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.md")
        try """
        ---
        title: Troy and Abed in the Morning
        date: 2024-01-01
        ---
        # Content
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.title == "Troy and Abed in the Morning")
    }

    @Test("Date extracted from ISO format")
    func dateExtractedFromISO() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.md")
        try """
        ---
        title: Test
        date: 2024-03-15
        ---
        Content
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.date != nil)

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: item.date!)
        #expect(components.year == 2024)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("Date extracted from TOML frontmatter")
    func dateExtractedFromTomlFrontmatter() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.md")
        try """
        +++
        title = "Senior Chang"
        date = 2024-05-02
        +++
        Content
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.date != nil)

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: item.date!)
        #expect(components.year == 2024)
        #expect(components.month == 5)
        #expect(components.day == 2)
    }

    @Test("Title and date extracted from JSON frontmatter")
    func jsonFrontmatterParsing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let postFile = tempDir.appendingPathComponent("test.markdown")
        try """
        {
          "title": "Dean Pelton",
          "date": "2024-08-20T12:34:56Z"
        }
        Content
        """.write(to: postFile, atomically: true, encoding: .utf8)

        let item = ContentItem(url: postFile, format: .file, section: "blog")
        #expect(item.title == "Dean Pelton")
        #expect(item.date != nil)
    }
}

@Suite("ContentFormat Tests")
struct ContentFormatTests {
    @Test("Bundle display name")
    func bundleDisplayName() {
        #expect(ContentFormat.bundle.displayName == "Bundle (folder/index.*)")
    }

    @Test("File display name")
    func fileDisplayName() {
        #expect(ContentFormat.file.displayName == "File (slug.*)")
    }

    @Test("All cases available")
    func allCasesAvailable() {
        #expect(ContentFormat.allCases.count == 2)
        #expect(ContentFormat.allCases.contains(.bundle))
        #expect(ContentFormat.allCases.contains(.file))
    }
}

@Suite("ContentSection Tests")
struct ContentSectionTests {
    @Test("Display name capitalizes first letter")
    func displayNameCapitalized() {
        let section = ContentSection(name: "blog", url: URL(fileURLWithPath: "/site/content/blog"), items: [])
        #expect(section.displayName == "Blog")
    }

    @Test("Item count reflects items array")
    func itemCountReflectsItems() {
        let items = [
            ContentItem(url: URL(fileURLWithPath: "/a.md"), format: .file, section: "blog"),
            ContentItem(url: URL(fileURLWithPath: "/b.md"), format: .file, section: "blog"),
        ]
        let section = ContentSection(name: "blog", url: URL(fileURLWithPath: "/site/content/blog"), items: items)
        #expect(section.itemCount == 2)
    }

    @Test("Sections sort with blog/posts/pages first")
    func sectionsSortWithPriority() {
        let docs = ContentSection(name: "docs", url: URL(fileURLWithPath: "/docs"), items: [])
        let blog = ContentSection(name: "blog", url: URL(fileURLWithPath: "/blog"), items: [])
        let pages = ContentSection(name: "pages", url: URL(fileURLWithPath: "/pages"), items: [])
        let about = ContentSection(name: "about", url: URL(fileURLWithPath: "/about"), items: [])

        let sorted = [docs, about, pages, blog].sorted()
        #expect(sorted.map(\.name) == ["blog", "pages", "about", "docs"])
    }
}

@Suite("WorkspaceRef Tests")
struct WorkspaceRefTests {
    @Test("Display name extracts folder name")
    func displayNameExtractsFolderName() {
        let ref = WorkspaceRef(path: "/tmp/Greendale/Study Group Notes", bookmarkData: Data())
        #expect(ref.displayName == "Study Group Notes")
    }

    @Test("ID equals path")
    func idEqualsPath() {
        let ref = WorkspaceRef(path: "/tmp/Greendale/Jeff/Documents", bookmarkData: Data())
        #expect(ref.id == "/tmp/Greendale/Jeff/Documents")
    }

    @Test("WorkspaceRef is equatable")
    func workspaceRefEquatable() {
        let ref1 = WorkspaceRef(path: "/test", bookmarkData: Data([1, 2, 3]))
        let ref2 = WorkspaceRef(path: "/test", bookmarkData: Data([1, 2, 3]))
        let ref3 = WorkspaceRef(path: "/other", bookmarkData: Data([1, 2, 3]))

        #expect(ref1 == ref2)
        #expect(ref1 != ref3)
    }
}

@Suite("WorkspaceError Tests")
struct WorkspaceErrorTests {
    @Test("Not Hugo site error description")
    func notHugoSiteError() {
        let error = WorkspaceError.notHugoSite
        #expect(error.localizedDescription.contains("hugo.toml"))
    }
}

@Suite("HugoConfig Tests")
struct HugoConfigTests {
    @Test("Default config values")
    func defaultConfigValues() {
        let config = HugoConfig.default
        #expect(config.contentDir == "content")
        #expect(config.archetypeDir == "archetypes")
        #expect(config.title == nil)
    }

    @Test("Loads from hugo.toml")
    func loadsFromHugoToml() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configFile = tempDir.appendingPathComponent("hugo.toml")
        try """
        title = "Greendale Blog"
        contentDir = "mycontent"
        archetypeDir = "myarchetypes"
        """.write(to: configFile, atomically: true, encoding: .utf8)

        let config = HugoConfig.load(from: tempDir)
        #expect(config.title == "Greendale Blog")
        #expect(config.contentDir == "mycontent")
        #expect(config.archetypeDir == "myarchetypes")
    }

    @Test("Falls back to default when no config")
    func fallsBackToDefault() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = HugoConfig.load(from: tempDir)
        #expect(config.contentDir == "content")
    }
}
