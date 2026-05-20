import Foundation
import Testing
@testable import Hugora

@Suite("Image Paste Options", .serialized)
struct ImagePasteOptionsTests {
    @Test("Default image paste format is PNG")
    func defaultImagePasteFormatIsPNG() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: DefaultsKey.imagePasteFormat)
        defer {
            if let original {
                defaults.set(original, forKey: DefaultsKey.imagePasteFormat)
            } else {
                defaults.removeObject(forKey: DefaultsKey.imagePasteFormat)
            }
        }

        defaults.removeObject(forKey: DefaultsKey.imagePasteFormat)
        #expect(ImagePasteFormat.current() == .png)
    }

    @Test("Image paste format and naming strategy read from defaults")
    func imagePasteOptionsReadFromDefaults() {
        let defaults = UserDefaults.standard
        let originalFormat = defaults.object(forKey: DefaultsKey.imagePasteFormat)
        let originalNaming = defaults.object(forKey: DefaultsKey.imagePasteNamingStrategy)
        defer {
            if let originalFormat {
                defaults.set(originalFormat, forKey: DefaultsKey.imagePasteFormat)
            } else {
                defaults.removeObject(forKey: DefaultsKey.imagePasteFormat)
            }

            if let originalNaming {
                defaults.set(originalNaming, forKey: DefaultsKey.imagePasteNamingStrategy)
            } else {
                defaults.removeObject(forKey: DefaultsKey.imagePasteNamingStrategy)
            }
        }

        defaults.set(ImagePasteFormat.jpeg.rawValue, forKey: DefaultsKey.imagePasteFormat)
        defaults.set(
            ImagePasteNamingStrategy.postSlugTimestamp.rawValue,
            forKey: DefaultsKey.imagePasteNamingStrategy
        )

        #expect(ImagePasteFormat.current() == .jpeg)
        #expect(ImagePasteNamingStrategy.current() == .postSlugTimestamp)
    }

    @Test("Image paste destination appends counter for existing filenames")
    func imagePasteDestinationAvoidsExistingFilenames() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let postURL = tempDir.appendingPathComponent("content/posts/post.md")
        try FileManager.default.createDirectory(
            at: postURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingImage = postURL.deletingLastPathComponent().appendingPathComponent("image.png")
        try Data([1]).write(to: existingImage)

        let context = ImageContext(postURL: postURL, siteURL: tempDir)
        let destination = ImagePasteDestinationAllocator.destination(
            context: context,
            location: .pageFolder,
            filename: "image.png"
        )

        #expect(destination.saveURL.lastPathComponent == "image-1.png")
        #expect(destination.markdownPath == "image-1.png")
    }

    @Test("Image paste destination preserves Hugo static markdown path")
    func imagePasteDestinationUsesStaticMarkdownPath() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let postURL = tempDir.appendingPathComponent("content/posts/post.md")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let context = ImageContext(postURL: postURL, siteURL: tempDir)
        let destination = ImagePasteDestinationAllocator.destination(
            context: context,
            location: .siteStatic,
            filename: "image.png"
        )

        #expect(destination.saveURL == tempDir.appendingPathComponent("static/image.png"))
        #expect(destination.markdownPath == "/image.png")
    }
}
