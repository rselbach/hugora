import AppKit
import Testing
@testable import Hugora

@Suite("EditorViewModel")
@MainActor
struct EditorViewModelTests {
    @Test("A loaded document receives WYSIWYG syntax hiding on its first style pass")
    func loadedDocumentIsStyled() throws {
        let text = "Before **bold** after"
        let viewModel = EditorViewModel()
        let textView = NSTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))

        viewModel.setText(text)
        viewModel.applyStyles(
            to: textView,
            visibleRange: NSRange(location: 0, length: text.utf16.count)
        )

        let markerLocation = (text as NSString).range(of: "**").location
        let markerFont = try #require(
            textView.textStorage?.attribute(.font, at: markerLocation, effectiveRange: nil) as? NSFont)
        #expect(markerFont.pointSize < 1)
    }

    @Test("Stale parsed documents are not applied to edited text")
    func staleParsedDocumentDoesNotStyleEditedText() {
        let viewModel = EditorViewModel(text: "# Heading")

        let initialTextView = NSTextView()
        initialTextView.string = "# Heading"
        viewModel.setText("# Heading")
        viewModel.applyStyles(
            to: initialTextView,
            visibleRange: NSRange(location: 0, length: initialTextView.string.utf16.count)
        )

        let editedTextView = NSTextView()
        editedTextView.string = "plain text"
        viewModel.updateTextFromEditor("plain text")
        viewModel.applyStyles(
            to: editedTextView,
            visibleRange: NSRange(location: 0, length: editedTextView.string.utf16.count)
        )

        if let font = editedTextView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            #expect(font.pointSize < Theme.defaultLight.headingStyle(level: 1).font.pointSize)
        }
    }
}
