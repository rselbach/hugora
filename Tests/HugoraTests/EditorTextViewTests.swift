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
                if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
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

    @Test("Theme paints editor and scroll backgrounds")
    @MainActor
    func applyThemePaintsEditorSurface() {
        let theme = Theme.rselbachCom
        let scrollView = NSScrollView()
        let textView = EditorTextView(frame: .zero)
        scrollView.documentView = textView

        textView.applyTheme(theme)

        #expect(textView.drawsBackground)
        #expect(scrollView.drawsBackground)
        #expect(scrollView.contentView.drawsBackground)
        #expect(textView.backgroundColor == theme.backgroundColor)
        #expect(scrollView.backgroundColor == theme.backgroundColor)
        #expect(scrollView.contentView.backgroundColor == theme.backgroundColor)
        #expect(textView.insertionPointColor == theme.baseColor)
    }
}

@Suite("EditorView Programmatic Loads")
struct EditorViewProgrammaticLoadTests {
    @Test("Loading a shorter document clamps the previous selection")
    @MainActor
    func clampsSelectionOnLoad() {
        let textView = NSTextView()
        textView.string = String(repeating: "long content ", count: 100)
        textView.setSelectedRange(NSRange(location: 500, length: 20))

        EditorView.loadProgrammaticText("short", into: textView)

        let selection = textView.selectedRange()
        #expect(NSMaxRange(selection) <= 5)
    }

    @Test("Loading a document clears the undo stack")
    @MainActor
    func clearsUndoStackOnLoad() {
        // A bare NSTextView has no undo manager; provide one via delegate
        // like a window-hosted text view would have.
        final class UndoProvidingDelegate: NSObject, NSTextViewDelegate {
            let manager = UndoManager()
            func undoManager(for view: NSTextView) -> UndoManager? { manager }
        }

        let delegate = UndoProvidingDelegate()
        let textView = NSTextView()
        textView.delegate = delegate
        textView.allowsUndo = true
        textView.string = "post A"

        // Simulate a user edit registered with the undo manager.
        textView.insertText(" edited", replacementRange: NSRange(location: 6, length: 0))
        #expect(delegate.manager.canUndo)

        EditorView.loadProgrammaticText("post B", into: textView)

        #expect(!delegate.manager.canUndo)
        #expect(textView.string == "post B")
    }
}
