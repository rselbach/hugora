import Foundation
import Testing
@testable import Hugora

@Suite("EditorState Rename")
struct EditorStateRenameTests {
    @Test("Auto-rename disabled keeps original path")
    func autoRenameDisabledKeepsOriginalPath() throws {
        let defaults = UserDefaults.standard
        let key = "autoRenameOnSave"
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(false, forKey: key)

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

    @Test("Auto-rename uses slug frontmatter when enabled")
    func autoRenameUsesSlugFrontmatterWhenEnabled() throws {
        let defaults = UserDefaults.standard
        let key = "autoRenameOnSave"
        let originalValue = defaults.object(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(true, forKey: key)

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
