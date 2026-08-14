import SwiftUI
@preconcurrency import AppKit
import Combine

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var viewModel: EditorViewModel
    var initialCursorPosition: Int = 0
    var initialScrollPosition: CGFloat = 0
    var focusMode = false
    var typewriterMode = false
    var onCursorChange: ((Int) -> Void)?
    var onScrollChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 50, height: 30)

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView

        context.coordinator.attach(textView: textView)
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.typewriterMode = typewriterMode
        viewModel.setFocusMode(focusMode)
        textView.imageContext = viewModel.imageContext
        textView.applyTheme(viewModel.editorTheme)

        DispatchQueue.main.async {
            self.restorePositions(textView: textView, scrollView: scrollView)
        }

        return scrollView
    }

    private func restorePositions(textView: NSTextView, scrollView: NSScrollView) {
        let maxPos = textView.string.utf16.count
        let clampedCursor = min(initialCursorPosition, maxPos)
        textView.setSelectedRange(NSRange(location: clampedCursor, length: 0))

        let maxScroll = max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentSize.height)
        let clampedScroll = min(initialScrollPosition, maxScroll)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: clampedScroll))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? EditorTextView else { return }

        textView.imageContext = viewModel.imageContext
        context.coordinator.typewriterMode = typewriterMode
        viewModel.setFocusMode(focusMode)

        // Skip if input method is composing (dead keys, IME) - touching the text view breaks composition
        guard !textView.hasMarkedText() else { return }
        textView.applyTheme(viewModel.editorTheme)

        // Don't sync text back if the change came from the text view itself
        if !context.coordinator.isUpdatingFromTextView && textView.string != text {
            Self.loadProgrammaticText(text, into: textView)
            // Keep parser state in sync for programmatic content loads (e.g. open file).
            viewModel.setText(text)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Replaces the text view content for a programmatic load (open file,
    /// switch post, session restore). The previous document's undo stack
    /// must not survive — Cmd+Z would replay its edits into the new text —
    /// and its selection has to be clamped to the new length or NSTextView
    /// raises NSRangeException.
    static func loadProgrammaticText(_ text: String, into textView: NSTextView) {
        let selectedRanges = textView.selectedRanges
        (textView as? EditorTextView)?.noteContentChanged()
        textView.string = text
        let maxLength = (text as NSString).length
        let clamped =
            selectedRanges
            .map(\.rangeValue)
            .filter { $0.location <= maxLength }
            .map { range in
                NSValue(
                    range: NSRange(
                        location: range.location,
                        length: min(range.length, maxLength - range.location)
                    ))
            }
        textView.selectedRanges = clamped.isEmpty ? [NSValue(range: NSRange(location: 0, length: 0))] : clamped
        textView.undoManager?.removeAllActions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, viewModel: viewModel)
    }

    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        let viewModel: EditorViewModel
        weak var textView: EditorTextView?
        var onCursorChange: ((Int) -> Void)?
        var onScrollChange: ((CGFloat) -> Void)?
        var typewriterMode = false
        private var isStyling = false
        private var scrollObserver: NSObjectProtocol?
        private var stylingCancellable: AnyCancellable?
        private var lastReportedScroll: CGFloat = 0
        var isUpdatingFromTextView = false

        init(text: Binding<String>, viewModel: EditorViewModel) {
            self.text = text
            self.viewModel = viewModel
            super.init()
            setupStylingPipeline()
        }

        func detach() {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            scrollObserver = nil
            textView = nil
        }

        func attach(textView: EditorTextView) {
            self.textView = textView
            configureScrollObserver()
            DispatchQueue.main.async { [weak self] in
                self?.triggerStyling()
                self?.reportScrollPosition()
            }
        }

        private func configureScrollObserver() {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
                scrollObserver = nil
            }

            guard let clipView = textView?.enclosingScrollView?.contentView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.triggerStyling()
                    self?.reportScrollPosition()
                }
            }
        }

        private func reportScrollPosition() {
            guard let scrollView = textView?.enclosingScrollView else { return }
            let scrollY = scrollView.contentView.bounds.origin.y
            if abs(scrollY - lastReportedScroll) > 10 {
                lastReportedScroll = scrollY
                onScrollChange?(scrollY)
            }
        }

        private func setupStylingPipeline() {
            stylingCancellable = viewModel.$text
                .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    self?.triggerStyling()
                }
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling else { return }
            guard let textView = notification.object as? EditorTextView else { return }
            // Don't interfere while input method is composing (dead keys, IME)
            guard !textView.hasMarkedText() else { return }
            textView.noteContentChanged()
            isUpdatingFromTextView = true
            text.wrappedValue = textView.string
            viewModel.updateTextFromEditor(textView.string)
            isUpdatingFromTextView = false
            triggerStyling()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView else { return }

            let cursorPos = textView.selectedRange().location
            viewModel.updateCursorPosition(cursorPos)
            onCursorChange?(cursorPos)
            if typewriterMode {
                centerSelection(textView)
            }
        }

        func triggerStyling() {
            guard let textView = textView else { return }
            // Don't style while input method is composing (dead keys, IME)
            guard !textView.hasMarkedText() else { return }

            isStyling = true
            defer { isStyling = false }

            let visibleRange = computeVisibleRange(textView: textView)
            viewModel.applyStyles(to: textView, visibleRange: visibleRange)
        }

        private func computeVisibleRange(textView: NSTextView) -> NSRange {
            computeRenderableRange(for: textView)
        }

        private func centerSelection(_ textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView,
                let layoutManager = textView.layoutManager
            else { return }

            let textLength = textView.string.utf16.count
            let cursor = min(textView.selectedRange().location, textLength)
            var rect: NSRect
            if cursor == textLength, layoutManager.extraLineFragmentTextContainer != nil {
                rect = layoutManager.extraLineFragmentRect
            } else {
                guard layoutManager.numberOfGlyphs > 0 else { return }
                let characterRange = NSRange(location: min(cursor, max(textLength - 1, 0)), length: 1)
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: characterRange, actualCharacterRange: nil)
                rect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            }
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            let maxY = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            let targetY = min(max(rect.midY - scrollView.contentView.bounds.height / 2, 0), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

#Preview {
    EditorView(
        text: .constant("# Hello World\n\nThis is some **bold** and *italic* text."),
        viewModel: EditorViewModel(text: "# Hello World\n\nThis is some **bold** and *italic* text.")
    )
    .frame(width: 600, height: 400)
}
