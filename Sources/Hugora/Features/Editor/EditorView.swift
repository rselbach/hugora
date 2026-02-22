import SwiftUI
import AppKit
import Combine

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var viewModel: EditorViewModel
    var initialCursorPosition: Int = 0
    var initialScrollPosition: CGFloat = 0
    var onCursorChange: ((Int) -> Void)?
    var onScrollChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
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
        textView.drawsBackground = false
        textView.backgroundColor = .clear

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView

        context.coordinator.attach(textView: textView)
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onScrollChange = onScrollChange
        textView.imageContext = viewModel.imageContext

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
        
        // Skip if input method is composing (dead keys, IME) - touching the text view breaks composition
        guard !textView.hasMarkedText() else { return }
        
        // Don't sync text back if the change came from the text view itself
        if !context.coordinator.isUpdatingFromTextView && textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
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

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func attach(textView: EditorTextView) {
            self.textView = textView
            configureScrollObserver()
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
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else {
                return NSRange(location: 0, length: textView.string.utf16.count)
            }

            let visibleRect = scrollView.documentVisibleRect
            let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
            var charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            let padding = 2000
            let start = max(0, charRange.location - padding)
            let end = min(textView.string.utf16.count, charRange.location + charRange.length + padding)
            charRange = NSRange(location: start, length: end - start)

            return charRange
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
