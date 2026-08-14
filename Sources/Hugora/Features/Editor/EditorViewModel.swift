import AppKit
import Combine
@preconcurrency import Markdown

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var text: String
    @Published var cursorPosition: Int = 0
    @Published private(set) var headings: [HeadingOutlineItem] = []

    private var styler: MarkdownStyler
    private let themeManager: ThemeManager
    private var cancellables = Set<AnyCancellable>()
    private var textRevision: UInt64 = 0
    private var parsedRevision: UInt64?
    private var currentDocument: Document?
    private let parseQueue = DispatchQueue(label: "com.hugora.parse", qos: .userInitiated)
    private weak var currentTextView: NSTextView?
    private var styleCache: StylePassCache?
    private var focusMode = false

    /// Context for resolving image paths. Set when opening a post.
    @Published var imageContext: ImageContext?

    private var cachedFontSize: Double?
    private var cachedLineSpacing: Double?

    var editorTheme: Theme {
        styler.theme
    }

    init(text: String = "", themeManager: ThemeManager? = nil) {
        let themeManager = themeManager ?? .shared
        self.text = text
        self.themeManager = themeManager
        self.styler = MarkdownStyler(theme: themeManager.currentTheme)
        setupPipeline()
        observeThemeChanges()
        observeEditorPreferences()
        observeImageLoads()
    }

    private func observeThemeChanges() {
        themeManager.$currentTheme
            .receive(on: RunLoop.main)
            .sink { [weak self] newTheme in
                self?.styler = MarkdownStyler(theme: newTheme)
                self?.forceRestyle()
            }
            .store(in: &cancellables)
    }

    private func observeEditorPreferences() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let defaults = UserDefaults.standard
                let currentFontSize = defaults.object(forKey: DefaultsKey.editorFontSize) as? Double ?? 16
                let currentLineSpacing = defaults.object(forKey: DefaultsKey.editorLineSpacing) as? Double ?? 1.4

                if cachedFontSize != currentFontSize || cachedLineSpacing != currentLineSpacing {
                    cachedFontSize = currentFontSize
                    cachedLineSpacing = currentLineSpacing
                    forceRestyle()
                }
            }
            .store(in: &cancellables)
    }

    private func observeImageLoads() {
        NotificationCenter.default.publisher(for: .asyncImageLoaderDidLoad)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.forceRestyle()
            }
            .store(in: &cancellables)
    }

    private func forceRestyle() {
        styleCache = nil
        guard let textView = currentTextView else { return }
        let visibleRange = computeRenderableRange(for: textView)
        applyStyles(to: textView, visibleRange: visibleRange)
    }

    private func setupPipeline() {
        $text
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] newText in
                guard let self else { return }
                self.parseAsync(newText, revision: self.textRevision)
            }
            .store(in: &cancellables)
    }

    private func parseAsync(_ text: String, revision: UInt64) {
        let capturedRevision = revision
        let textCopy = text

        parseQueue.async { [weak self] in
            let doc = Document(parsing: textCopy, options: [.parseBlockDirectives, .parseSymbolLinks])
            var outlineCollector = HeadingOutlineCollector(text: textCopy)
            outlineCollector.visit(doc)
            let headings = outlineCollector.headings

            DispatchQueue.main.async { [weak self] in
                guard let self, self.textRevision == capturedRevision else { return }
                self.currentDocument = doc
                self.headings = headings
                self.parsedRevision = capturedRevision
                self.forceRestyle()
            }
        }
    }

    func applyStyles(to textView: NSTextView, visibleRange: NSRange) {
        currentTextView = textView
        cursorPosition = textView.selectedRange().location

        if let editorTextView = textView as? EditorTextView {
            editorTextView.applyTheme(styler.theme)
        }

        guard let textStorage = textView.textStorage else { return }
        guard let doc = currentDocument else {
            parseSync()
            guard let doc = currentDocument else { return }
            styleCache = styler.applyStyles(
                to: textStorage, in: visibleRange, document: doc, cursorPosition: cursorPosition,
                imageContext: imageContext)
            applyFocusMode(to: textStorage, visibleRange: visibleRange)
            return
        }

        guard parsedRevision == textRevision else { return }
        styleCache = styler.applyStyles(
            to: textStorage, in: visibleRange, document: doc, cursorPosition: cursorPosition, imageContext: imageContext
        )
        applyFocusMode(to: textStorage, visibleRange: visibleRange)
    }

    func updateCursorPosition(_ position: Int) {
        guard position != cursorPosition else { return }
        let oldPosition = cursorPosition
        cursorPosition = position

        if focusMode {
            forceRestyle()
            return
        }

        guard let cache = styleCache,
            let textView = currentTextView,
            let textStorage = textView.textStorage
        else {
            forceRestyle()
            return
        }

        textStorage.beginEditing()
        styler.updateCursorStyles(
            in: textStorage,
            cache: cache,
            oldCursor: oldPosition,
            newCursor: position,
            imageContext: imageContext
        )
        textStorage.endEditing()
    }

    private func parseSync() {
        currentDocument = Document(parsing: text, options: [.parseBlockDirectives, .parseSymbolLinks])
        if let currentDocument {
            var outlineCollector = HeadingOutlineCollector(text: text)
            outlineCollector.visit(currentDocument)
            headings = outlineCollector.headings
        }
        parsedRevision = textRevision
    }

    func setFocusMode(_ enabled: Bool) {
        guard focusMode != enabled else { return }
        focusMode = enabled
        forceRestyle()
    }

    func selectAndReveal(_ range: NSRange) {
        guard let textView = currentTextView else { return }
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textView.string.utf16.count))
        let insertionRange = NSRange(location: clampedRange.location, length: 0)
        textView.setSelectedRange(insertionRange)
        textView.scrollRangeToVisible(insertionRange)
        textView.window?.makeFirstResponder(textView)
    }

    private func applyFocusMode(to textStorage: NSTextStorage, visibleRange: NSRange) {
        guard focusMode, textStorage.length > 0 else { return }
        let cursor = min(cursorPosition, textStorage.length)
        let paragraphRange = (textStorage.string as NSString).paragraphRange(
            for: NSRange(location: cursor, length: 0))
        for range in Self.dimmedRanges(visibleRange: visibleRange, focusedRange: paragraphRange) {
            textStorage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                guard let color = value as? NSColor else { return }
                textStorage.addAttribute(.foregroundColor, value: color.withAlphaComponent(0.28), range: subrange)
            }
        }
    }

    nonisolated static func dimmedRanges(visibleRange: NSRange, focusedRange: NSRange) -> [NSRange] {
        let focused = NSIntersectionRange(visibleRange, focusedRange)
        guard focused.length > 0 else { return visibleRange.length > 0 ? [visibleRange] : [] }
        var ranges: [NSRange] = []
        if focused.location > visibleRange.location {
            ranges.append(NSRange(location: visibleRange.location, length: focused.location - visibleRange.location))
        }
        if NSMaxRange(focused) < NSMaxRange(visibleRange) {
            ranges.append(
                NSRange(location: NSMaxRange(focused), length: NSMaxRange(visibleRange) - NSMaxRange(focused)))
        }
        return ranges
    }

    func setText(_ newText: String) {
        textRevision &+= 1
        text = newText
        parseSync()
        forceRestyle()
    }

    func updateTextFromEditor(_ newText: String) {
        textRevision &+= 1
        text = newText
        headings = []
        styleCache = nil
    }
}
