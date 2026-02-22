import Foundation
import Testing
@testable import Hugora

@Suite("EditorState", .serialized)
struct EditorStateTests {
    // All UserDefaults keys touched by EditorState tests.
    private static let touchedKeys = [
        "autoRenameOnSave",
        "hugora.session.currentPost",
        "hugora.workspace.bookmark",
    ]

    private func withCleanDefaults(_ body: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let saved = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, original) in saved {
                if let original { defaults.set(original, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try await body()
    }

    @Test("Auto-rename disabled keeps original path")
    @MainActor
    func autoRenameDisabledKeepsOriginalPath() async throws {
        try await withCleanDefaults {
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

            let slug = Slug.from("Greendale Community College Rules")
            let renamedURL = tempDir.appendingPathComponent("2024-06-20-\(slug).md")
            #expect(!FileManager.default.fileExists(atPath: renamedURL.path))
        }
    }

    @Test("Auto-rename uses slug frontmatter when enabled")
    @MainActor
    func autoRenameUsesSlugFrontmatterWhenEnabled() async throws {
        try await withCleanDefaults {
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

    @Test("Session restore is skipped without workspace bookmark")
    @MainActor
    func restoreSkippedWithoutWorkspaceBookmark() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("post.md")
            try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

            defaults.set(fileURL.path, forKey: "hugora.session.currentPost")
            defaults.removeObject(forKey: "hugora.workspace.bookmark")

            let state = EditorState()
            try await Task.sleep(nanoseconds: 50_000_000)

            #expect(state.currentItem == nil)
        }
    }

    @Test("Session restore succeeds when file is within bookmarked workspace")
    @MainActor
    func restoreAllowedWithinWorkspaceBookmark() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let workspaceDir = tempDir.appendingPathComponent("workspace")
            try FileManager.default.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = workspaceDir.appendingPathComponent("post.md")
            try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

            let bookmarkData = try workspaceDir.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmarkData, forKey: "hugora.workspace.bookmark")
            defaults.set(fileURL.path, forKey: "hugora.session.currentPost")

            let state = EditorState()
            try await Task.sleep(nanoseconds: 100_000_000)

            #expect(state.currentItem?.url.standardizedFileURL.path == fileURL.standardizedFileURL.path)
        }
    }
}
