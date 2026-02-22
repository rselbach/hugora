import SwiftUI
import AppKit
import Combine
import os

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

class EditorTextView: NSTextView {
    private var fontSize: Double = 16
    private var lineSpacing: Double = 1.4
    private var spellCheckEnabled = true
    private var autoPairEnabled = true
    
    /// Context for saving pasted images. Set by the coordinator.
    var imageContext: ImageContext?

    /// Indicates an image paste operation is in progress.
    var isPastingImage = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "EditorTextView"
    )

    private static let pairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "*": "*",
        "_": "_",
        "`": "`"
    ]

    private static let openers: Set<Character> = Set(pairs.keys)
    private static let closers: Set<Character> = Set(pairs.values)
    private static let symmetricPairs: Set<Character> = ["*", "_", "`"]
    private var defaultsObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    deinit {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setup() {
        applyPreferences()
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        smartInsertDeleteEnabled = false

        usesFindBar = true
        isIncrementalSearchingEnabled = true

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPreferences()
        }
    }

    private func applyPreferences() {
        let defaults = UserDefaults.standard
        let storedFontSize = defaults.object(forKey: DefaultsKey.editorFontSize) as? Double
        let storedLineSpacing = defaults.object(forKey: DefaultsKey.editorLineSpacing) as? Double
        fontSize = max(storedFontSize ?? 16, 1)
        lineSpacing = max(storedLineSpacing ?? 1.4, 1)
        spellCheckEnabled = defaults.object(forKey: DefaultsKey.spellCheckEnabled) as? Bool ?? true
        autoPairEnabled = defaults.object(forKey: DefaultsKey.autoPairEnabled) as? Bool ?? true

        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        isContinuousSpellCheckingEnabled = spellCheckEnabled
        updateTypingAttributes()
    }

    private func updateTypingAttributes() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineSpacing

        typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
    }
    
    override func insertText(_ string: Any, replacementRange: NSRange) {
        
        // If input method is composing (dead keys, IME), skip auto-pairing entirely
        let isComposing = hasMarkedText() || replacementRange.location != NSNotFound
        
        guard autoPairEnabled,
              !isComposing,
              let insertedString = string as? String,
              insertedString.count == 1,
              let char = insertedString.first else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }

        let selectedRange = self.selectedRange()
        let hasSelection = selectedRange.length > 0

        if hasSelection, let closer = Self.pairs[char] {
            wrapSelection(opener: char, closer: closer, range: selectedRange)
            return
        }

        if let closer = Self.pairs[char], !Self.symmetricPairs.contains(char) {
            insertPair(opener: char, closer: closer)
            return
        }

        if Self.symmetricPairs.contains(char) {
            if shouldSkipOver(char: char, at: selectedRange.location) {
                moveCursorRight()
                return
            }
            insertPair(opener: char, closer: char)
            return
        }

        if Self.closers.contains(char), shouldSkipOver(char: char, at: selectedRange.location) {
            moveCursorRight()
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        guard autoPairEnabled else {
            super.deleteBackward(sender)
    
            return
        }

        let selectedRange = self.selectedRange()
        guard selectedRange.length == 0, selectedRange.location > 0 else {
            super.deleteBackward(sender)
    
            return
        }

        let nsString = (self.string as NSString)
        let prevLocation = selectedRange.location - 1
        guard let prevScalar = UnicodeScalar(nsString.character(at: prevLocation)) else {
            super.deleteBackward(sender)
            return
        }
        let prevChar = Character(prevScalar)

        guard let expectedCloser = Self.pairs[prevChar],
              selectedRange.location < nsString.length else {
            super.deleteBackward(sender)
            return
        }

        guard let nextScalar = UnicodeScalar(nsString.character(at: selectedRange.location)) else {
            super.deleteBackward(sender)
            return
        }
        let nextChar = Character(nextScalar)

        guard nextChar == expectedCloser else {
            super.deleteBackward(sender)
            return
        }

        let deleteRange = NSRange(location: prevLocation, length: 2)
        if shouldChangeText(in: deleteRange, replacementString: "") {
            replaceCharacters(in: deleteRange, with: "")
            didChangeText()
        }
    }

    private func wrapSelection(opener: Character, closer: Character, range: NSRange) {
        let nsString = (self.string as NSString)
        let selectedText = nsString.substring(with: range)
        let wrapped = "\(opener)\(selectedText)\(closer)"

        if shouldChangeText(in: range, replacementString: wrapped) {
            replaceCharacters(in: range, with: wrapped)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + 1, length: range.length))
        }
    }

    private func insertPair(opener: Character, closer: Character) {
        let range = self.selectedRange()
        let pair = "\(opener)\(closer)"

        if shouldChangeText(in: range, replacementString: pair) {
            replaceCharacters(in: range, with: pair)
            didChangeText()
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
        }
    }

    private func shouldSkipOver(char: Character, at location: Int) -> Bool {
        let nsString = (self.string as NSString)
        guard location < nsString.length,
              let scalar = UnicodeScalar(nsString.character(at: location)) else {
            return false
        }
        let nextChar = Character(scalar)
        return nextChar == char
    }

    private func moveCursorRight() {
        let range = self.selectedRange()
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
    }
    
    // MARK: - Custom Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockquoteBorders(in: dirtyRect)
        drawRenderedImages(in: dirtyRect)
        drawImagePasteIndicator(in: dirtyRect)
    }

    private func drawImagePasteIndicator(in dirtyRect: NSRect) {
        guard isPastingImage else { return }

        let bounds = bounds
        let progressFrame = NSRect(
            x: bounds.midX - 20,
            y: bounds.midY - 20,
            width: 40,
            height: 40
        )

        guard progressFrame.intersects(dirtyRect) else { return }

        let bgRect = NSRect(
            x: progressFrame.minX - 10,
            y: progressFrame.minY - 10,
            width: progressFrame.width + 20,
            height: progressFrame.height + 20
        )

        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 8, yRadius: 8)

        NSGraphicsContext.saveGraphicsState()
        bgPath.addClip()

        NSColor.black.withAlphaComponent(0.7).setFill()
        bgPath.fill()

        let center = NSPoint(x: progressFrame.midX, y: progressFrame.midY)
        let radius: CGFloat = 12
        let lineWidth: CGFloat = 3

        NSColor.white.setStroke()
        let trackPath = NSBezierPath()
        trackPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360
        )
        trackPath.lineWidth = lineWidth
        trackPath.stroke()

        let time = Date().timeIntervalSince1970 * 2
        let endAngle = 360 * (time.truncatingRemainder(dividingBy: 1.0))
        let progressPath = NSBezierPath()
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: endAngle,
            clockwise: false
        )
        progressPath.lineWidth = lineWidth
        progressPath.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }
    
    // MARK: - Blockquote Border Drawing
    
    private func drawBlockquoteBorders(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let borderWidth: CGFloat = 3
        let borderInset: CGFloat = 16  // matches the paragraph indent step
        
        // Find visible character range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        
        textStorage.enumerateAttribute(.blockquoteInfo, in: visibleCharRange, options: []) { value, range, _ in
            guard let info = value as? BlockquoteInfo else { return }
            
            // Get the line fragment rects for this blockquote range
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, usedRect, container, lineGlyphRange, stop in
                // Calculate border position based on nesting level
                // Each level gets a border at a different x position
                for level in 1...info.nestingLevel {
                    let borderX = self.textContainerOrigin.x + CGFloat(level - 1) * borderInset + 2
                    let lineY = lineRect.origin.y + self.textContainerOrigin.y
                    
                    let borderRect = NSRect(
                        x: borderX,
                        y: lineY,
                        width: borderWidth,
                        height: lineRect.height
                    )
                    
                    // Only draw if it intersects the dirty rect
                    guard borderRect.intersects(dirtyRect) else { continue }
                    
                    // Draw the border
                    info.borderColor.setFill()
                    let path = NSBezierPath(roundedRect: borderRect, xRadius: 1.5, yRadius: 1.5)
                    path.fill()
                }
            }
        }
    }
    
    private func drawRenderedImages(in dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = layoutManager,
              let textContainer = textContainer else { return }
        
        let cursorLocation = selectedRange().location
        let maxWidth: CGFloat = 600
        
        // Find all image ranges in the visible area
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        
        textStorage.enumerateAttribute(.renderedImage, in: visibleCharRange, options: []) { value, range, _ in
            guard let imageInfo = value as? RenderedImageInfo else { return }
            
            // Don't draw if cursor is inside this image's markdown
            let cursorInImage = cursorLocation >= range.location && cursorLocation <= NSMaxRange(range)
            if cursorInImage { return }
            
            // Get the bounding rect for the entire image markdown range
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            // Calculate scaled image size
            let originalSize = imageInfo.originalSize
            var targetSize = originalSize
            if originalSize.width > maxWidth {
                let scale = maxWidth / originalSize.width
                targetSize = NSSize(width: maxWidth, height: originalSize.height * scale)
            }
            
            // Draw image below the markdown text, accounting for text container inset
            // The bounding rect gives us where the (hidden) markdown text is
            let imageRect = NSRect(
                x: textContainerOrigin.x,
                y: boundingRect.maxY + textContainerOrigin.y + 6,  // below the hidden markdown
                width: targetSize.width,
                height: targetSize.height
            )
            
            // Only draw if image rect intersects dirty rect
            guard imageRect.intersects(dirtyRect) else { return }
            
            // Draw with rounded corners and shadow
            let path = NSBezierPath(roundedRect: imageRect, xRadius: 4, yRadius: 4)
            
            NSGraphicsContext.saveGraphicsState()
            
            // Shadow
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 4
            shadow.set()
            
            // Clip to rounded rect
            path.addClip()
            
            // Draw image with proper orientation for flipped view
            // NSTextView is flipped, so we need to flip the image drawing
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                
                // Flip the context for this image
                context.translateBy(x: imageRect.origin.x, y: imageRect.origin.y + imageRect.height)
                context.scaleBy(x: 1.0, y: -1.0)
                
                let drawRect = CGRect(origin: .zero, size: imageRect.size)
                imageInfo.image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                
                context.restoreGState()
            }
            
            NSGraphicsContext.restoreGraphicsState()
            
            // Draw border
            NSColor.separatorColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
    }
    
    // MARK: - Image Paste
    
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        types.insert(NSPasteboard.PasteboardType("public.png"), at: 0)
        types.insert(.tiff, at: 0)
        return types
    }
    
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        
        if let image = pasteboardImage(from: pasteboard) {
            handleImagePaste(image)
            return
        }
        
        super.paste(sender)
    }
    
    private func pasteboardImage(from pasteboard: NSPasteboard) -> NSImage? {
        // Try PNG first (preferred for quality) - use UTType string directly
        let pngType = NSPasteboard.PasteboardType("public.png")
        if let pngData = pasteboard.data(forType: pngType),
           let image = NSImage(data: pngData) {
            return image
        }
        
        // Try TIFF (common for screenshots)
        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return image
        }
        
        // Try file URLs pointing to images
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"]
        ]) as? [URL], let url = urls.first {
            return NSImage(contentsOf: url)
        }
        
        return nil
    }
    
    private func handleImagePaste(_ image: NSImage) {
        guard let context = imageContext else {
            let alert = NSAlert()
            alert.messageText = "Cannot paste image"
            alert.informativeText = "No post is currently open. Open a post first to paste images."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        isPastingImage = true
        needsDisplay = true

        let filename = generateImageFilename()
        let location = ImagePasteLocation.current()
        let destination = imagePasteDestination(context: context, location: location, filename: filename)

        do {
            try FileManager.default.createDirectory(
                at: destination.saveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            isPastingImage = false
            needsDisplay = true
            let alert = NSAlert()
            alert.messageText = "Failed to prepare image folder"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        guard saveImageAsPNG(image, to: destination.saveURL) else {
            isPastingImage = false
            needsDisplay = true
            let alert = NSAlert()
            alert.messageText = "Failed to save image"
            alert.informativeText = "Could not save the image to \(destination.saveURL.path)"
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        isPastingImage = false
        let markdown = "![](\(destination.markdownPath))"
        insertText(markdown, replacementRange: selectedRange())
    }

    private func imagePasteDestination(
        context: ImageContext,
        location: ImagePasteLocation,
        filename: String
    ) -> (saveURL: URL, markdownPath: String) {
        switch location {
        case .pageFolder:
            let postDirectory = context.postURL.deletingLastPathComponent()
            return (postDirectory.appendingPathComponent(filename), filename)
        case .siteStatic:
            let staticDirectory = context.siteURL.appendingPathComponent("static")
            return (staticDirectory.appendingPathComponent(filename), "/\(filename)")
        case .siteAssets:
            let assetsDirectory = context.siteURL.appendingPathComponent("assets")
            return (assetsDirectory.appendingPathComponent(filename), "assets/\(filename)")
        }
    }
    
    private static let imageTimestampFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    private func generateImageFilename() -> String {
        let timestamp = Self.imageTimestampFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "")
        return "image-\(timestamp).png"
    }
    
    private func saveImageAsPNG(_ image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return false
        }
        
        do {
            try pngData.write(to: url)
            return true
        } catch {
            Self.logger.error("Failed to save image: \(error.localizedDescription)")
            return false
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
