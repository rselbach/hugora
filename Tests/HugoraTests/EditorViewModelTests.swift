import AppKit
import Testing
@testable import Hugora

@Suite("EditorViewModel")
@MainActor
struct EditorViewModelTests {
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
