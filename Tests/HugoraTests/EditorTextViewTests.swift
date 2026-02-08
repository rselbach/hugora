import AppKit
import Foundation
import Testing
@testable import Hugora

@Suite("EditorTextView Preferences")
struct EditorTextViewPreferencesTests {

    // All UserDefaults keys that these tests (or the code under test) touch.
    private static let touchedKeys = [
        "editorFontSize",
        "editorLineSpacing",
        "spellCheckEnabled",
        "autoPairEnabled",
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

    @Test("Applies UserDefaults changes without crashing")
    @MainActor
    func appliesDefaultsUpdates() throws {
        try withCleanDefaults {
            let defaults = UserDefaults.standard

            defaults.set(14.0, forKey: "editorFontSize")
            defaults.set(1.3, forKey: "editorLineSpacing")
            defaults.set(true, forKey: "spellCheckEnabled")
            defaults.set(true, forKey: "autoPairEnabled")

            let textView = EditorTextView(frame: .zero)

            defaults.set(20.0, forKey: "editorFontSize")
            defaults.set(1.8, forKey: "editorLineSpacing")
            defaults.set(false, forKey: "spellCheckEnabled")
            defaults.set(false, forKey: "autoPairEnabled")

            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))

            #expect(textView.font?.pointSize == 20)
            #expect(textView.isContinuousSpellCheckingEnabled == false)

            let paragraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            #expect(paragraphStyle != nil)

            if let paragraphStyle {
                #expect(abs(paragraphStyle.lineHeightMultiple - 1.8) < 0.001)
            }
        }
    }
}
