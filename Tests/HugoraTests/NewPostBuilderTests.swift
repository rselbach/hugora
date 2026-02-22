import Foundation
import Testing
@testable import Hugora

@Suite("NewPostBuilder")
struct NewPostBuilderTests {
    @Test("Bundle archetype prefers section index template")
    func bundleArchetypePrefersSectionIndex() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let archetypesDir = tempDir.appendingPathComponent("archetypes")
        let sectionDir = archetypesDir.appendingPathComponent("posts")
        try FileManager.default.createDirectory(at: sectionDir, withIntermediateDirectories: true)

        let indexTemplateURL = sectionDir.appendingPathComponent("index.md")
        let sectionTemplateURL = archetypesDir.appendingPathComponent("posts.md")

        try """
        ---
        source: "index"
        title: "{{ .Title }}"
        date: "{{ .Date }}"
        slug: "{{ .Slug }}"
        type: "{{ .Type }}"
        ---
        """.write(to: indexTemplateURL, atomically: true, encoding: .utf8)

        try """
        ---
        source: "section"
        title: "{{ .Title }}"
        ---
        """.write(to: sectionTemplateURL, atomically: true, encoding: .utf8)

        let config = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)
        let builder = NewPostBuilder(siteURL: tempDir, config: config)
        let date = Date(timeIntervalSince1970: 0)
        let content = builder.buildContent(
            sectionName: "posts",
            format: .bundle,
            title: "Troy Barnes",
            slug: "troy-barnes",
            date: date
        )

        #expect(content.contains("source: \"index\""))
        #expect(!content.contains("source: \"section\""))
        #expect(content.contains("title: \"Troy Barnes\""))
        #expect(content.contains("date: \"1970-01-01T00:00:00Z\""))
        #expect(content.contains("slug: \"troy-barnes\""))
        #expect(content.contains("type: \"posts\""))
    }

    @Test("File archetype prefers section template")
    func fileArchetypePrefersSectionTemplate() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let archetypesDir = tempDir.appendingPathComponent("archetypes")
        try FileManager.default.createDirectory(at: archetypesDir, withIntermediateDirectories: true)

        let sectionTemplateURL = archetypesDir.appendingPathComponent("posts.md")
        let defaultTemplateURL = archetypesDir.appendingPathComponent("default.md")

        try """
        ---
        source: "section"
        title: "{{ .Title }}"
        ---
        """.write(to: sectionTemplateURL, atomically: true, encoding: .utf8)

        try """
        ---
        source: "default"
        ---
        """.write(to: defaultTemplateURL, atomically: true, encoding: .utf8)

        let config = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)
        let builder = NewPostBuilder(siteURL: tempDir, config: config)
        let content = builder.buildContent(
            sectionName: "posts",
            format: .file,
            title: "Greendale Rules",
            slug: "greendale-rules",
            date: Date(timeIntervalSince1970: 0)
        )

        #expect(content.contains("source: \"section\""))
        #expect(!content.contains("source: \"default\""))
        #expect(content.contains("title: \"Greendale Rules\""))
    }

    @Test("Defaults used when no archetype exists")
    func defaultFrontmatterWhenNoArchetype() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let config = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)
        let builder = NewPostBuilder(siteURL: tempDir, config: config)
        let content = builder.buildContent(
            sectionName: "posts",
            format: .file,
            title: "Community Movie",
            slug: "community-movie",
            date: Date(timeIntervalSince1970: 0)
        )

        #expect(content.contains("title: \"Community Movie\""))
        #expect(content.contains("draft: true"))
    }

    @Test("Escaped archetypeDir falls back to in-site archetypes directory")
    func escapedArchetypeDirFallsBackToSafeDefault() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("hugora-parent-\(UUID().uuidString)")
        let siteDir = parent.appendingPathComponent("site")
        let siblingDir = parent.appendingPathComponent("site2")
        let fm = FileManager.default

        try fm.createDirectory(at: siteDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: siblingDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: parent) }

        // Safe fallback archetype inside the site.
        let safeArchetypes = siteDir.appendingPathComponent("archetypes")
        try fm.createDirectory(at: safeArchetypes, withIntermediateDirectories: true)
        try """
        ---
        source: "safe"
        title: "{{ .Title }}"
        ---
        """.write(to: safeArchetypes.appendingPathComponent("default.md"), atomically: true, encoding: .utf8)

        // Escaped archetype dir should be ignored.
        let escapedArchetypes = siblingDir.appendingPathComponent("archetypes")
        try fm.createDirectory(at: escapedArchetypes, withIntermediateDirectories: true)
        try """
        ---
        source: "escaped"
        title: "{{ .Title }}"
        ---
        """.write(to: escapedArchetypes.appendingPathComponent("default.md"), atomically: true, encoding: .utf8)

        let config = HugoConfig(contentDir: "content", archetypeDir: "../site2/archetypes", title: nil)
        let builder = NewPostBuilder(siteURL: siteDir, config: config)
        let content = builder.buildContent(
            sectionName: "posts",
            format: .file,
            title: "Greendale News",
            slug: "greendale-news",
            date: Date(timeIntervalSince1970: 0)
        )

        #expect(content.contains("source: \"safe\""))
        #expect(!content.contains("source: \"escaped\""))
    }
}
