import Foundation
import Testing
@testable import Hugora

@Suite("EditorState Rename")
struct EditorStateRenameTests {

    // All UserDefaults keys that these tests (or the code under test) touch.
    // Saved before and restored after each test to prevent cross-test pollution.
    private static let touchedKeys = [
        "autoRenameOnSave",
        "hugora.session.currentPost",
    ]

    /// Snapshot current values, run body, then restore originals.
    private func withCleanDefaults(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let saved = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, original) in saved {
                if let original { defaults.set(original, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try body()
    }

    @Test("Auto-rename disabled keeps original path")
    @MainActor
    func autoRenameDisabledKeepsOriginalPath() throws {
        try withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("2024-01-01-old-post.md")
            let initialContent = """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            Old content
            """
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

            let item = ContentItem(url: fileURL, format: .file, section: "blog")
            let state = EditorState()
            state.openItem(item)

            let updatedContent = """
            ---
            title: "Greendale Community College Rules"
            date: 2024-06-20
            ---
            Updated content
            """
            state.updateContent(updatedContent)
            state.save()

            #expect(FileManager.default.fileExists(atPath: fileURL.path))

            let slug = slugify("Greendale Community College Rules")
            let renamedURL = tempDir.appendingPathComponent("2024-06-20-\(slug).md")
            #expect(!FileManager.default.fileExists(atPath: renamedURL.path))
        }
    }

    @Test("Auto-rename uses slug frontmatter when enabled")
    @MainActor
    func autoRenameUsesSlugFrontmatterWhenEnabled() throws {
        try withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("2024-01-01-old-post.md")
            let initialContent = """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            Old content
            """
            try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

            let item = ContentItem(url: fileURL, format: .file, section: "blog")
            let state = EditorState()
            state.openItem(item)

            let updatedContent = """
            ---
            title: "Annie Edison"
            slug: "human-being"
            date: 2024-06-20
            ---
            Updated content
            """
            state.updateContent(updatedContent)
            state.save()

            let renamedURL = tempDir.appendingPathComponent("2024-06-20-human-being.md")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }
}
