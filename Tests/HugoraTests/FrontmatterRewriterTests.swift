import Foundation
import Testing

@testable import Hugora

@Suite("FrontmatterRewriter")
struct FrontmatterRewriterTests {
    @Test("Replaces a YAML scalar in place, preserving everything else")
    func replacesYAMLScalar() throws {
        let doc = """
            ---
            title: "Old Title"
            date: 2024-01-01
            draft: true
            ---

            Body stays put.
            """

        let result = try #require(FrontmatterRewriter.set("title", to: .string("Troy Barnes"), in: doc))
        #expect(result.contains("title: \"Troy Barnes\""))
        #expect(result.contains("date: 2024-01-01"))
        #expect(result.contains("draft: true"))
        #expect(result.contains("Body stays put."))
        #expect(!result.contains("Old Title"))
    }

    @Test("Appends a missing YAML key before the closing delimiter")
    func appendsYAMLKey() throws {
        let doc = """
            ---
            title: "Post"
            ---
            Body
            """

        let result = try #require(FrontmatterRewriter.set("draft", to: .bool(false), in: doc))
        let expected = """
            ---
            title: "Post"
            draft: false
            ---
            Body
            """
        #expect(result == expected)
    }

    @Test("Replaces a YAML block array with an inline array")
    func replacesYAMLBlockArray() throws {
        let doc = """
            ---
            title: "Post"
            tags:
              - old-tag
              - another
            date: 2024-01-01
            ---
            Body
            """

        let result = try #require(
            FrontmatterRewriter.set("tags", to: .stringArray(["go", "hugo"]), in: doc)
        )
        #expect(result.contains("tags: [\"go\", \"hugo\"]"))
        #expect(!result.contains("- old-tag"))
        #expect(result.contains("date: 2024-01-01"))
    }

    @Test("Handles zero-indented YAML block sequences")
    func replacesZeroIndentedSequence() throws {
        let doc = """
            ---
            tags:
            - alpha
            - beta
            title: "Post"
            ---
            Body
            """

        let result = try #require(FrontmatterRewriter.set("tags", to: .stringArray(["only"]), in: doc))
        #expect(result.contains("tags: [\"only\"]"))
        #expect(!result.contains("- alpha"))
        #expect(result.contains("title: \"Post\""))
    }

    @Test("Replaces a TOML scalar and multi-line array")
    func rewritesTOML() throws {
        let doc = """
            +++
            title = "Old"
            aliases = [
              "/a",
              "/b",
            ]
            draft = true
            +++
            Body
            """

        let withTitle = try #require(FrontmatterRewriter.set("title", to: .string("New"), in: doc))
        #expect(withTitle.contains("title = \"New\""))

        let withAliases = try #require(
            FrontmatterRewriter.set("aliases", to: .stringArray(["/a", "/b", "/c"]), in: withTitle)
        )
        #expect(withAliases.contains("aliases = [\"/a\", \"/b\", \"/c\"]"))
        #expect(!withAliases.contains("  \"/a\","))
        #expect(withAliases.contains("draft = true"))
    }

    @Test("Rewrites JSON frontmatter")
    func rewritesJSON() throws {
        let doc = """
            {
              "title": "Old",
              "draft": true
            }
            Body
            """

        let result = try #require(FrontmatterRewriter.set("title", to: .string("New"), in: doc))
        #expect(result.contains("\"title\" : \"New\"") || result.contains("\"title\": \"New\""))
        #expect(result.contains("Body"))
    }

    @Test("Removes a key including its block continuation")
    func removesKey() throws {
        let doc = """
            ---
            title: "Post"
            tags:
              - a
              - b
            ---
            Body
            """

        let result = try #require(FrontmatterRewriter.remove("tags", in: doc))
        let expected = """
            ---
            title: "Post"
            ---
            Body
            """
        #expect(result == expected)
        #expect(FrontmatterRewriter.remove("absent", in: doc) == doc)
    }

    @Test("Escapes quotes and backslashes in written strings")
    func escapesStrings() throws {
        let doc = """
            ---
            title: "Old"
            ---
            """

        let result = try #require(
            FrontmatterRewriter.set("title", to: .string(#"He said "hi" \ bye"#), in: doc)
        )
        #expect(result.contains(#"title: "He said \"hi\" \\ bye""#))
    }

    @Test("Raw values are written unquoted")
    func rawValueUnquoted() throws {
        let doc = """
            ---
            title: "Post"
            date: 2020-01-01
            ---
            """

        let result = try #require(
            FrontmatterRewriter.set("date", to: .raw("2026-07-13T10:00:00-04:00"), in: doc)
        )
        #expect(result.contains("date: 2026-07-13T10:00:00-04:00"))
        #expect(!result.contains("\"2026-07-13"))
    }

    @Test("Key matching is case-insensitive but preserves document format")
    func caseInsensitiveKeys() throws {
        let doc = """
            ---
            Title: "Old"
            ---
            """

        let result = try #require(FrontmatterRewriter.set("title", to: .string("New"), in: doc))
        #expect(result.contains(": \"New\""))
        #expect(!result.contains("Old"))
        // Only one title line remains.
        let titleLines = result.components(separatedBy: "\n").filter {
            $0.lowercased().hasPrefix("title")
        }
        #expect(titleLines.count == 1)
    }

    @Test("Documents without frontmatter return nil")
    func noFrontmatter() {
        #expect(FrontmatterRewriter.set("title", to: .string("x"), in: "Just a body") == nil)
    }
}
