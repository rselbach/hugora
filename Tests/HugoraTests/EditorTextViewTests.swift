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

@Suite("Markdown Formatting")
struct MarkdownFormattingTests {
    @MainActor
    private func makeEditor(_ text: String, selection: NSRange) -> EditorTextView {
        let textView = EditorTextView(frame: .zero)
        textView.string = text
        textView.setSelectedRange(selection)
        return textView
    }

    @Test("Bold wraps the selection and leaves it selected")
    @MainActor
    func boldWrapsSelection() {
        let editor = makeEditor("make this bold", selection: NSRange(location: 5, length: 4))
        editor.toggleBold(nil)
        #expect(editor.string == "make **this** bold")
        #expect(editor.selectedRange() == NSRange(location: 7, length: 4))
    }

    @Test("Bold applied twice round-trips")
    @MainActor
    func boldTogglesOff() {
        let editor = makeEditor("make this bold", selection: NSRange(location: 5, length: 4))
        editor.toggleBold(nil)
        editor.toggleBold(nil)
        #expect(editor.string == "make this bold")
        #expect(editor.selectedRange() == NSRange(location: 5, length: 4))
    }

    @Test("Bold with markers inside the selection unwraps")
    @MainActor
    func boldUnwrapsSelectedMarkers() {
        let editor = makeEditor("a **bold** word", selection: NSRange(location: 2, length: 8))
        editor.toggleBold(nil)
        #expect(editor.string == "a bold word")
    }

    @Test("Italic without selection inserts pair with cursor inside")
    @MainActor
    func italicEmptySelection() {
        let editor = makeEditor("hello ", selection: NSRange(location: 6, length: 0))
        editor.toggleItalic(nil)
        #expect(editor.string == "hello **")
        #expect(editor.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test("Insert link uses selection as text and selects the url placeholder")
    @MainActor
    func insertLinkSelectsPlaceholder() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("definitely not a link", forType: .string)

        let editor = makeEditor("see the docs here", selection: NSRange(location: 8, length: 4))
        editor.insertLinkMarkup(nil)
        #expect(editor.string == "see the [docs](url) here")

        let selection = editor.selectedRange()
        #expect((editor.string as NSString).substring(with: selection) == "url")
    }

    @Test("Insert link uses a URL from the clipboard")
    @MainActor
    func insertLinkUsesClipboardURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://rselbach.com/post/", forType: .string)

        let editor = makeEditor("see the docs here", selection: NSRange(location: 8, length: 4))
        editor.insertLinkMarkup(nil)
        #expect(editor.string == "see the [docs](https://rselbach.com/post/) here")
    }

    @Test("Summary divider lands on its own line")
    @MainActor
    func summaryDividerOwnLine() {
        let editor = makeEditor("intro paragraph", selection: NSRange(location: 15, length: 0))
        editor.insertSummaryDivider(nil)
        #expect(editor.string == "intro paragraph\n<!--more-->\n")
    }
}

@Suite("Context-Aware Auto-Pair")
struct AutoPairContextTests {
    @MainActor
    private func makeEditor(_ text: String, cursor: Int) -> EditorTextView {
        let textView = EditorTextView(frame: .zero)
        textView.string = text
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        return textView
    }

    @Test("Asterisk at line start does not pair (list bullet)")
    @MainActor
    func asteriskAtLineStartDoesNotPair() {
        let editor = makeEditor("first line\n", cursor: 11)
        editor.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "first line\n*")
    }

    @Test("Underscore inside a word does not pair (snake_case)")
    @MainActor
    func underscoreInWordDoesNotPair() {
        let editor = makeEditor("my", cursor: 2)
        editor.insertText("_", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "my_")
    }

    @Test("Asterisk after a space still pairs")
    @MainActor
    func asteriskAfterSpacePairs() {
        let editor = makeEditor("some ", cursor: 5)
        editor.insertText("*", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "some **")
        #expect(editor.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("Backtick after a word still pairs")
    @MainActor
    func backtickAfterWordPairs() {
        let editor = makeEditor("code", cursor: 4)
        editor.insertText("`", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.string == "code``")
    }
}

@Suite("Shortcode Insertion")
struct ShortcodeInsertionTests {
    @Test("Built-in templates carry their selection placeholder")
    func templatesAreConsistent() {
        for shortcode in ShortcodeCatalog.builtIn {
            #expect(shortcode.template.contains(shortcode.name))
            if let placeholder = shortcode.selectionPlaceholder {
                #expect(shortcode.template.contains(placeholder))
            }
        }
    }

    @Test("Inserting a template selects the placeholder")
    @MainActor
    func insertSelectsPlaceholder() {
        let editor = EditorTextView(frame: .zero)
        editor.string = "before "
        editor.setSelectedRange(NSRange(location: 7, length: 0))

        editor.insertShortcodeTemplate(ShortcodeCatalog.builtIn.first { $0.name == "youtube" }!)

        #expect(editor.string == "before {{< youtube VIDEO_ID >}}")
        let selection = editor.selectedRange()
        #expect((editor.string as NSString).substring(with: selection) == "VIDEO_ID")
    }
}

@Suite("Post Link Insertion")
struct PostLinkInsertionTests {
    @Test("relrefPath is content-root relative")
    func relrefPathComputation() {
        let contentRoot = URL(fileURLWithPath: "/site/content")

        let filePost = ContentItem(
            url: URL(fileURLWithPath: "/site/content/posts/2024-06-20-troy.md"),
            format: .file, section: "posts",
            content: "---\ntitle: Troy\n---"
        )
        #expect(filePost.relrefPath(contentRoot: contentRoot) == "/posts/2024-06-20-troy.md")

        let bundlePost = ContentItem(
            url: URL(fileURLWithPath: "/site/content/blog/my-bundle/index.md"),
            format: .bundle, section: "blog",
            content: "---\ntitle: Bundle\n---"
        )
        #expect(bundlePost.relrefPath(contentRoot: contentRoot) == "/blog/my-bundle/index.md")

        let outside = ContentItem(
            url: URL(fileURLWithPath: "/elsewhere/post.md"),
            format: .file, section: "posts",
            content: "---\ntitle: Outside\n---"
        )
        #expect(outside.relrefPath(contentRoot: contentRoot) == nil)
    }

    @Test("Selection becomes the link text")
    @MainActor
    func selectionBecomesLinkText() {
        let editor = EditorTextView(frame: .zero)
        editor.string = "read my older post about that"
        editor.setSelectedRange(NSRange(location: 8, length: 10))

        editor.insertPostLink(relrefPath: "/posts/older.md", fallbackText: "Older Post")

        #expect(editor.string == #"read my [older post]({{< relref "/posts/older.md" >}}) about that"#)
    }

    @Test("Without a selection the title is inserted and selected")
    @MainActor
    func fallbackTitleSelected() {
        let editor = EditorTextView(frame: .zero)
        editor.string = "see "
        editor.setSelectedRange(NSRange(location: 4, length: 0))

        editor.insertPostLink(relrefPath: "/posts/older.md", fallbackText: "Older Post")

        #expect(editor.string == #"see [Older Post]({{< relref "/posts/older.md" >}})"#)
        let selection = editor.selectedRange()
        #expect((editor.string as NSString).substring(with: selection) == "Older Post")
    }
}

@Suite("Image Paste Markdown")
struct ImagePasteMarkdownTests {
    @Test("Alt text derives from the file name")
    @MainActor
    func altTextFromFilename() {
        let (markdown, altRange) = EditorTextView.imageMarkdown(forPath: "cover-photo_final.png")
        #expect(markdown == "![cover photo final](cover-photo_final.png)")
        #expect((markdown as NSString).substring(with: altRange) == "cover photo final")
    }

    @Test("Paths keep directories out of the alt text")
    @MainActor
    func altTextIgnoresDirectories() {
        let (markdown, altRange) = EditorTextView.imageMarkdown(forPath: "/images/2024/troy-barnes.jpg")
        #expect(markdown == "![troy barnes](/images/2024/troy-barnes.jpg)")
        #expect((markdown as NSString).substring(with: altRange) == "troy barnes")
    }
}
