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
}
