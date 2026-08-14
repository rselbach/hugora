import Foundation
import Testing
@testable import Hugora

@Suite("EditorState", .serialized)
struct EditorStateTests {
    // All UserDefaults keys touched by EditorState tests.
    private static let touchedKeys = [
        "autoSaveEnabled",
        "autoRenameOnSave",
        "addAliasOnRename",
        "hugora.session.currentPost",
        "hugora.workspace.bookmark",
    ]

    private func withCleanDefaults(_ body: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let saved = Self.touchedKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, original) in saved {
                if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        try await body()
    }

    @MainActor
    private func waitForLoad(_ state: EditorState) async throws {
        for _ in 0..<100 where state.isLoading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!state.isLoading)
    }

    @Test("Auto-rename disabled keeps original path")
    @MainActor
    func autoRenameDisabledKeepsOriginalPath() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
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
            try await waitForLoad(state)

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
            defaults.set(false, forKey: "autoSaveEnabled")
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
            try await waitForLoad(state)

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

    @Test("Auto-rename preserves the original file extension and index name")
    @MainActor
    func autoRenamePreservesExtension() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // A .markdown flat file must stay .markdown after the rename.
            let fileURL = tempDir.appendingPathComponent("2024-01-01-old-post.markdown")
            try """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            """.write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: fileURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent(
                """
                ---
                title: "Shirley Bennett"
                date: 2024-06-20
                ---
                """)
            state.save()

            let renamedURL = tempDir.appendingPathComponent("2024-06-20-shirley-bennett.markdown")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))
            #expect(state.currentItem?.url == renamedURL)

            // A bundle keeps its index filename when the folder is renamed.
            let bundleDir = tempDir.appendingPathComponent("2024-01-01-old-bundle")
            try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
            let indexURL = bundleDir.appendingPathComponent("index.markdown")
            try """
            ---
            title: "Old Bundle"
            date: 2024-01-01
            ---
            """.write(to: indexURL, atomically: true, encoding: .utf8)

            let bundleState = EditorState()
            bundleState.openItem(ContentItem(url: indexURL, format: .bundle, section: "blog"))
            try await waitForLoad(bundleState)
            bundleState.updateContent(
                """
                ---
                title: "Ben Chang"
                date: 2024-06-21
                ---
                """)
            bundleState.save()

            let renamedIndexURL =
                tempDir
                .appendingPathComponent("2024-06-21-ben-chang")
                .appendingPathComponent("index.markdown")
            #expect(FileManager.default.fileExists(atPath: renamedIndexURL.path))
            #expect(bundleState.currentItem?.url == renamedIndexURL)
        }
    }

    @Test("Auto-rename parses non-ISO frontmatter dates")
    @MainActor
    func autoRenameParsesNonISODates() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("2024-01-01-old-post.md")
            try """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            Old content
            """.write(to: fileURL, atomically: true, encoding: .utf8)

            let item = ContentItem(url: fileURL, format: .file, section: "blog")
            let state = EditorState()
            state.openItem(item)
            try await waitForLoad(state)

            state.updateContent(
                """
                ---
                title: "Troy Barnes"
                date: "Jan 2, 2025"
                ---
                Updated content
                """)
            state.save()

            let renamedURL = tempDir.appendingPathComponent("2025-01-02-troy-barnes.md")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))
            #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        }
    }

    @Test("Renaming a published post records the old URL as an alias")
    @MainActor
    func renameAddsAliasForPublishedPost() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")
            defaults.set(true, forKey: "addAliasOnRename")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let postsDir = tempDir.appendingPathComponent("content/posts")
            try FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = postsDir.appendingPathComponent("2024-01-01-old-slug.md")
            try """
            ---
            title: "Old Slug"
            date: 2024-01-01
            draft: false
            ---
            Body
            """.write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.hugoConfig = HugoConfig(
                contentDir: "content", archetypeDir: "archetypes", title: nil,
                baseURL: "https://greendale.edu"
            )
            state.openItem(ContentItem(url: fileURL, format: .file, section: "posts"))
            try await waitForLoad(state)
            state.updateContent(
                """
                ---
                title: "Shiny New Slug"
                date: 2024-01-01
                draft: false
                ---
                Body
                """)
            state.save()

            let renamedURL = postsDir.appendingPathComponent("2024-01-01-shiny-new-slug.md")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))

            let saved = try String(contentsOf: renamedURL, encoding: .utf8)
            #expect(saved.contains(#"aliases: ["/posts/2024-01-01-old-slug/"]"#))
            #expect(state.content.contains("aliases:"))
            #expect(state.isDirty == false)
        }
    }

    @Test("Renaming a draft does not add an alias")
    @MainActor
    func renameDraftAddsNoAlias() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")
            defaults.set(true, forKey: "addAliasOnRename")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("2024-01-01-old.md")
            try """
            ---
            title: "Old"
            date: 2024-01-01
            draft: true
            ---
            """.write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.hugoConfig = HugoConfig(
                contentDir: "content", archetypeDir: "archetypes", title: nil,
                baseURL: "https://greendale.edu"
            )
            state.openItem(ContentItem(url: fileURL, format: .file, section: "posts"))
            try await waitForLoad(state)
            state.updateContent(
                """
                ---
                title: "Renamed Draft"
                date: 2024-01-01
                draft: true
                ---
                """)
            state.save()

            let renamedURL = tempDir.appendingPathComponent("2024-01-01-renamed-draft.md")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))
            let saved = try String(contentsOf: renamedURL, encoding: .utf8)
            #expect(!saved.contains("aliases"))
        }
    }

    @Test("Auto-rename fails when target path already exists")
    @MainActor
    func autoRenameCollisionLeavesOriginalFileUntouched() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let originalURL = tempDir.appendingPathComponent("2024-01-01-old-post.md")
            try """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            Original
            """.write(to: originalURL, atomically: true, encoding: .utf8)

            let collisionURL = tempDir.appendingPathComponent("2024-06-20-human-being.md")
            try """
            ---
            title: "Existing"
            date: 2024-06-20
            ---
            Existing
            """.write(to: collisionURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: originalURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent(
                """
                ---
                title: "Annie Edison"
                slug: "human-being"
                date: 2024-06-20
                ---
                Updated content
                """)
            state.save()

            #expect(FileManager.default.fileExists(atPath: originalURL.path))
            #expect(FileManager.default.fileExists(atPath: collisionURL.path))

            let collisionContent = try String(contentsOf: collisionURL, encoding: .utf8)
            #expect(collisionContent.contains("Existing"))
            #expect(state.isDirty == true)
            #expect(state.lastError != nil)
            #expect(state.lastError?.localizedDescription.contains("Cannot rename") == true)
        }
    }

    @Test("Auto-rename never lets garbage frontmatter escape the content root")
    @MainActor
    func autoRenameSanitizesGarbageFrontmatter() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let contentDir = tempDir.appendingPathComponent("content/posts")
            try FileManager.default.createDirectory(at: contentDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let originalURL = contentDir.appendingPathComponent("2024-01-01-old-post.md")
            try """
            ---
            title: "Old Post"
            date: 2024-01-01
            ---
            Original
            """.write(to: originalURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.contentRootURL = tempDir.appendingPathComponent("content")
            state.openItem(ContentItem(url: originalURL, format: .file, section: "posts"))
            try await waitForLoad(state)
            state.updateContent(
                """
                ---
                title: "Unsafe Rename"
                slug: "human-being"
                date: ../../oops
                ---
                Updated content
                """)
            state.save()

            // The unparseable date falls back to the item's original date,
            // so the rename stays inside the content root instead of
            // producing a traversal path.
            let renamedURL = contentDir.appendingPathComponent("2024-01-01-human-being.md")
            #expect(FileManager.default.fileExists(atPath: renamedURL.path))
            #expect(!FileManager.default.fileExists(atPath: originalURL.path))
            #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("oops-human-being.md").path))
            #expect(state.isDirty == false)
            #expect(state.lastError == nil)
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

    @Test("Auto-save writes changes when enabled")
    @MainActor
    func autoSavePersistsWhenEnabled() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "autoSaveEnabled")
            defaults.set(false, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("post.md")
            try "old".write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: fileURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent("new")

            try await Task.sleep(nanoseconds: 1_200_000_000)
            let stored = try String(contentsOf: fileURL, encoding: .utf8)

            #expect(stored == "new")
            #expect(state.isDirty == false)
        }
    }

    @Test("Auto-save does not persist changes when disabled")
    @MainActor
    func autoSaveDoesNotPersistWhenDisabled() async throws {
        try await withCleanDefaults {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "autoSaveEnabled")
            defaults.set(false, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let fileURL = tempDir.appendingPathComponent("post.md")
            try "old".write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: fileURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent("new")

            try await Task.sleep(nanoseconds: 1_200_000_000)
            let stored = try String(contentsOf: fileURL, encoding: .utf8)

            #expect(stored == "old")
            #expect(state.isDirty == true)
        }
    }

    @Test("Failed save prevents navigation and preserves the buffer")
    @MainActor
    func failedSavePreventsNavigation() async throws {
        try await withCleanDefaults {
            UserDefaults.standard.set(false, forKey: "autoSaveEnabled")
            UserDefaults.standard.set(true, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let firstURL = tempDir.appendingPathComponent("2024-01-01-first.md")
            let secondURL = tempDir.appendingPathComponent("second.md")
            try "---\ntitle: First\ndate: 2024-01-01\n---\nOld".write(
                to: firstURL, atomically: true, encoding: .utf8)
            try "Second".write(to: secondURL, atomically: true, encoding: .utf8)
            let collisionURL = tempDir.appendingPathComponent("2024-01-01-new-title.md")
            try "Collision".write(to: collisionURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: firstURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            let unsaved = "---\ntitle: New Title\ndate: 2024-01-01\n---\nUnsaved"
            state.updateContent(unsaved)

            state.openItem(ContentItem(url: secondURL, format: .file, section: "blog"))

            #expect(state.currentItem?.url == firstURL)
            #expect(state.content == unsaved)
            #expect(state.isDirty)
            #expect(state.lastError != nil)
        }
    }

    @Test("External file changes are not overwritten")
    @MainActor
    func externalChangesAreNotOverwritten() async throws {
        try await withCleanDefaults {
            UserDefaults.standard.set(false, forKey: "autoSaveEnabled")
            UserDefaults.standard.set(false, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            let fileURL = tempDir.appendingPathComponent("post.md")
            try "Original".write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: fileURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent("Hugora edit")
            try "External edit".write(to: fileURL, atomically: true, encoding: .utf8)

            #expect(!state.save())
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "External edit")
            #expect(state.isDirty)
            #expect(state.lastError as? EditorStateError == .externallyModified(fileURL.path))
        }
    }

    @Test("Closing a document cancels pending saves and clears state")
    @MainActor
    func closeCurrentDocumentClearsState() async throws {
        try await withCleanDefaults {
            UserDefaults.standard.set(true, forKey: "autoSaveEnabled")
            UserDefaults.standard.set(false, forKey: "autoRenameOnSave")

            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }
            let fileURL = tempDir.appendingPathComponent("post.md")
            try "Original".write(to: fileURL, atomically: true, encoding: .utf8)

            let state = EditorState()
            state.openItem(ContentItem(url: fileURL, format: .file, section: "blog"))
            try await waitForLoad(state)
            state.updateContent("Pending")
            state.closeCurrentDocument()
            try await Task.sleep(nanoseconds: 1_100_000_000)

            #expect(state.currentItem == nil)
            #expect(state.content.isEmpty)
            #expect(!state.isDirty)
            #expect(try String(contentsOf: fileURL, encoding: .utf8) == "Original")
        }
    }
}
