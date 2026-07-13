import Foundation
import Testing

@testable import Hugora

@Suite("PermalinkResolver")
struct PermalinkResolverTests {
    private func makeItem(
        path: String = "/site/content/posts/2024-06-20-my-post.md",
        section: String = "posts",
        content: String
    ) -> ContentItem {
        ContentItem(
            url: URL(fileURLWithPath: path),
            format: .file,
            section: section,
            content: content
        )
    }

    @Test("Default permalink is /section/slug/")
    func defaultPermalink() {
        let content = """
            ---
            title: My Post
            date: 2024-06-20
            ---
            """
        let item = makeItem(content: content)
        let config = HugoConfig(
            contentDir: "content", archetypeDir: "archetypes", title: nil,
            baseURL: "https://rselbach.com/"
        )

        let permalink = PermalinkResolver.permalink(content: content, item: item, config: config)
        #expect(permalink == "https://rselbach.com/posts/2024-06-20-my-post/")
    }

    @Test("Frontmatter slug overrides the filename")
    func slugOverride() {
        let content = """
            ---
            title: My Post
            slug: pretty-slug
            date: 2024-06-20
            ---
            """
        let item = makeItem(content: content)
        let config = HugoConfig(
            contentDir: "content", archetypeDir: "archetypes", title: nil,
            baseURL: "https://rselbach.com"
        )

        let permalink = PermalinkResolver.permalink(content: content, item: item, config: config)
        #expect(permalink == "https://rselbach.com/posts/pretty-slug/")
    }

    @Test("Configured permalink pattern expands date tokens")
    func patternExpansion() {
        let content = """
            ---
            title: My Post
            slug: pretty-slug
            date: 2024-06-20
            ---
            """
        let item = makeItem(content: content)
        let config = HugoConfig(
            contentDir: "content", archetypeDir: "archetypes", title: nil,
            baseURL: "https://rselbach.com",
            permalinks: ["posts": "/:year/:month/:slug/"]
        )

        let permalink = PermalinkResolver.permalink(content: content, item: item, config: config)
        #expect(permalink == "https://rselbach.com/2024/06/pretty-slug/")
    }

    @Test("Frontmatter url wins over everything")
    func explicitURL() {
        let content = """
            ---
            title: My Post
            url: /special/place
            date: 2024-06-20
            ---
            """
        let item = makeItem(content: content)
        let config = HugoConfig(
            contentDir: "content", archetypeDir: "archetypes", title: nil,
            baseURL: "https://rselbach.com",
            permalinks: ["posts": "/:year/:slug/"]
        )

        let permalink = PermalinkResolver.permalink(content: content, item: item, config: config)
        #expect(permalink == "https://rselbach.com/special/place/")
    }

    @Test("baseURL with a subpath is preserved")
    func baseURLSubpath() {
        let content = """
            ---
            title: My Post
            date: 2024-06-20
            ---
            """
        let item = makeItem(content: content)
        let config = HugoConfig(
            contentDir: "content", archetypeDir: "archetypes", title: nil,
            baseURL: "https://example.com/blog/"
        )

        let permalink = PermalinkResolver.permalink(content: content, item: item, config: config)
        #expect(permalink == "https://example.com/blog/posts/2024-06-20-my-post/")
    }

    @Test("Missing baseURL yields no permalink")
    func missingBaseURL() {
        let content = "---\ntitle: X\n---"
        let item = makeItem(content: content)
        let config = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)

        #expect(PermalinkResolver.permalink(content: content, item: item, config: config) == nil)
    }

    @Test("Permalinks parse from config including page-nested form")
    func configParsing() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        baseURL = "https://rselbach.com/"
        title = "Blog"

        [permalinks.page]
        posts = "/:year/:month/:slug/"
        """.write(to: tempDir.appendingPathComponent("hugo.toml"), atomically: true, encoding: .utf8)

        let config = HugoConfig.load(from: tempDir)
        #expect(config.baseURL == "https://rselbach.com/")
        #expect(config.permalinks["posts"] == "/:year/:month/:slug/")
    }
}
