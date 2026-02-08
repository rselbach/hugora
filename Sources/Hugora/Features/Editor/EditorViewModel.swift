import AppKit
import Combine
import Markdown

final class EditorViewModel: ObservableObject {
    @Published var text: String
    @Published var cursorPosition: Int = 0

    private var styler: MarkdownStyler
    private let themeManager: ThemeManager
    private var cancellables = Set<AnyCancellable>()
    private var revision: UInt64 = 0
    private var currentDocument: Document?
    private let parseQueue = DispatchQueue(label: "com.hugora.parse", qos: .userInitiated)
    private weak var currentTextView: NSTextView?
    private var styleCache: StylePassCache?
    
    /// Context for resolving image paths. Set when opening a post.
    @Published var imageContext: ImageContext?

    init(text: String = "", themeManager: ThemeManager = .shared) {
        self.text = text
        self.themeManager = themeManager
        self.styler = MarkdownStyler(theme: themeManager.currentTheme)
        setupPipeline()
        observeThemeChanges()
        observeEditorPreferences()
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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.forceRestyle()
            }
            .store(in: &cancellables)
    }

    private func forceRestyle() {
        styleCache = nil
        guard let textView = currentTextView else { return }
        let visibleRange = NSRange(location: 0, length: textView.string.utf16.count)
        applyStyles(to: textView, visibleRange: visibleRange)
    }

    private func setupPipeline() {
        $text
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] newText in
                self?.parseAsync(newText)
            }
            .store(in: &cancellables)
    }

    private func parseAsync(_ text: String) {
        revision &+= 1
        let capturedRevision = revision
        let textCopy = text

        parseQueue.async { [weak self] in
            let doc = Document(parsing: textCopy, options: [.parseBlockDirectives, .parseSymbolLinks])

            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == capturedRevision else { return }
                self.currentDocument = doc
            }
        }
    }

    func applyStyles(to textView: NSTextView, visibleRange: NSRange) {
        currentTextView = textView
        cursorPosition = textView.selectedRange().location

        guard let textStorage = textView.textStorage else { return }
        guard let doc = currentDocument else {
            parseSync()
            guard let doc = currentDocument else { return }
            textStorage.beginEditing()
            styleCache = styler.applyStyles(to: textStorage, in: visibleRange, document: doc, cursorPosition: cursorPosition, imageContext: imageContext)
            textStorage.endEditing()
            return
        }

        textStorage.beginEditing()
        styleCache = styler.applyStyles(to: textStorage, in: visibleRange, document: doc, cursorPosition: cursorPosition, imageContext: imageContext)
        textStorage.endEditing()
    }
    
    func updateCursorPosition(_ position: Int) {
        guard position != cursorPosition else { return }
        let oldPosition = cursorPosition
        cursorPosition = position

        guard let cache = styleCache,
              let textView = currentTextView,
              let textStorage = textView.textStorage else {
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
    }

    func forceReparse() {
        styleCache = nil
        parseSync()
    }

    func setText(_ newText: String) {
        text = newText
        parseSync()
        forceRestyle()
    }
}
