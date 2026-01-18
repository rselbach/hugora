import Testing
import Foundation
@testable import Hugora

@Suite("BlogPost Tests")
struct BlogPostTests {
    @Test("Bundle format extracts slug from parent directory")
    func bundleSlugFromParent() {
        let url = URL(fileURLWithPath: "/site/content/blog/my-cool-post/index.md")
        let post = BlogPost(url: url, format: .bundle)

        #expect(post.slug == "my-cool-post")
        #expect(post.format == .bundle)
    }

    @Test("File format extracts slug from filename")
    func fileSlugFromFilename() {
        let url = URL(fileURLWithPath: "/site/content/blog/another-post.md")
        let post = BlogPost(url: url, format: .file)

        #expect(post.slug == "another-post")
        #expect(post.format == .file)
    }

    @Test("Title falls back to slug when no frontmatter")
    func titleFallsBackToSlug() {
        let url = URL(fileURLWithPath: "/nonexistent/post-slug.md")
        let post = BlogPost(url: url, format: .file)

        #expect(post.title == "post-slug")
    }

    @Test("Posts with dates sort newest first")
    func postsWithDatesSortNewestFirst() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldPost = tempDir.appendingPathComponent("old-post.md")
        try """
        ---
        title: "Old Post"
        date: 2023-01-15
        ---
        Old content
        """.write(to: oldPost, atomically: true, encoding: .utf8)

        let newPost = tempDir.appendingPathComponent("new-post.md")
        try """
        ---
        title: "New Post"
        date: 2024-06-20
        ---
        New content
        """.write(to: newPost, atomically: true, encoding: .utf8)

        let old = BlogPost(url: oldPost, format: .file)
        let new = BlogPost(url: newPost, format: .file)

        #expect(new < old)  // newer sorts first
    }

    @Test("Posts without dates sort alphabetically")
    func postsWithoutDatesSortAlphabetically() {
        let aPost = BlogPost(url: URL(fileURLWithPath: "/site/content/blog/aardvark.md"), format: .file)
        let zPost = BlogPost(url: URL(fileURLWithPath: "/site/content/blog/zebra.md"), format: .file)

        #expect(aPost < zPost)
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

        let post = BlogPost(url: postFile, format: .file)
        #expect(post.title == "Greendale Community College Rules")
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

        let post = BlogPost(url: postFile, format: .file)
        #expect(post.title == "Troy and Abed in the Morning")
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

        let post = BlogPost(url: postFile, format: .file)
        #expect(post.date != nil)

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: post.date!)
        #expect(components.year == 2024)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }
}

@Suite("PostFormat Tests")
struct PostFormatTests {
    @Test("Bundle display name")
    func bundleDisplayName() {
        #expect(PostFormat.bundle.displayName == "Bundle (folder/index.md)")
    }

    @Test("File display name")
    func fileDisplayName() {
        #expect(PostFormat.file.displayName == "File (slug.md)")
    }

    @Test("All cases available")
    func allCasesAvailable() {
        #expect(PostFormat.allCases.count == 2)
        #expect(PostFormat.allCases.contains(.bundle))
        #expect(PostFormat.allCases.contains(.file))
    }
}

@Suite("WorkspaceRef Tests")
struct WorkspaceRefTests {
    @Test("Display name extracts folder name")
    func displayNameExtractsFolderName() {
        let ref = WorkspaceRef(path: "/Users/annie/Documents/Study Group Notes", bookmarkData: Data())
        #expect(ref.displayName == "Study Group Notes")
    }

    @Test("ID equals path")
    func idEqualsPath() {
        let ref = WorkspaceRef(path: "/Users/jeff/Documents", bookmarkData: Data())
        #expect(ref.id == "/Users/jeff/Documents")
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

    @Test("No blog directory error description")
    func noBlogDirectoryError() {
        let error = WorkspaceError.noBlogDirectory
        #expect(error.localizedDescription.contains("content/blog"))
    }
}
