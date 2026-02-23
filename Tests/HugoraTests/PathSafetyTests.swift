import Foundation
import Testing
@testable import Hugora

@Suite("PathSafety")
struct PathSafetyTests {
    @Test("Same path is allowed")
    func samePathAllowed() {
        let root = URL(fileURLWithPath: "/tmp/greendale/site")
        #expect(PathSafety.isSameOrDescendant(root, of: root))
    }

    @Test("Nested path is allowed")
    func nestedPathAllowed() {
        let root = URL(fileURLWithPath: "/tmp/greendale/site")
        let nested = root.appendingPathComponent("content/posts/human-being.md")
        #expect(PathSafety.isSameOrDescendant(nested, of: root))
    }

    @Test("Prefix-only sibling is rejected")
    func prefixSiblingRejected() {
        let root = URL(fileURLWithPath: "/tmp/greendale/site")
        let sibling = URL(fileURLWithPath: "/tmp/greendale/site2/content/post.md")
        #expect(!PathSafety.isSameOrDescendant(sibling, of: root))
    }

    @Test("Parent path is rejected")
    func parentPathRejected() {
        let root = URL(fileURLWithPath: "/tmp/greendale/site/content")
        let parent = URL(fileURLWithPath: "/tmp/greendale")
        #expect(!PathSafety.isSameOrDescendant(parent, of: root))
    }

    @Test("Symlink escaping workspace is rejected")
    func symlinkEscapeRejected() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("pathsafety-\(UUID().uuidString)")
        let workspace = base.appendingPathComponent("site")
        let outsideDir = base.appendingPathComponent("secrets")
        let symlinkInside = workspace.appendingPathComponent("content/evil")

        try fm.createDirectory(at: workspace.appendingPathComponent("content"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: symlinkInside, withDestinationURL: outsideDir)
        defer { try? fm.removeItem(at: base) }

        #expect(!PathSafety.isSameOrDescendant(symlinkInside, of: workspace))
    }
}
