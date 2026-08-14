import AppKit
import os

class EditorTextView: NSTextView {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "EditorTextView"
    )
    private var fontSize: Double = 16
    private var lineSpacing: Double = 1.4
    private var spellCheckEnabled = true
    private var autoPairEnabled = true
    private var currentTheme = Theme.defaultLight

    /// Context for saving pasted images. Set by the coordinator.
    var imageContext: ImageContext?

    /// Indicates an image paste operation is in progress.
    var isPastingImage = false {
        didSet {
            if isPastingImage {
                startSpinnerTimer()
            } else {
                stopSpinnerTimer()
            }
        }
    }
    private var spinnerTimer: Timer?
    private(set) var contentRevision: UInt64 = 0

    private static let pairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "*": "*",
        "_": "_",
        "`": "`",
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
        spinnerTimer?.invalidate()
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

    func noteContentChanged() {
        contentRevision &+= 1
    }

    func canCompleteImagePaste(revision: UInt64, postURL: URL) -> Bool {
        contentRevision == revision
            && imageContext?.postURL.standardizedFileURL == postURL.standardizedFileURL
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

    func applyTheme(_ theme: Theme) {
        currentTheme = theme
        let backgroundColor = theme.backgroundColor

        drawsBackground = true
        self.backgroundColor = backgroundColor
        insertionPointColor = theme.baseColor
        updateTypingAttributes()

        guard let scrollView = enclosingScrollView else { return }
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = backgroundColor
    }

    private func updateTypingAttributes() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineSpacing

        typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: currentTheme.baseColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {

        // If input method is composing (dead keys, IME), skip auto-pairing entirely
        let isComposing = hasMarkedText() || replacementRange.location != NSNotFound

        guard autoPairEnabled,
            !isComposing,
            let insertedString = string as? String,
            insertedString.count == 1,
            let char = insertedString.first
        else {
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
            guard shouldAutoPairSymmetric(char, at: selectedRange.location) else {
                super.insertText(string, replacementRange: replacementRange)
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
            selectedRange.location < nsString.length
        else {
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

    /// Emphasis markers shouldn't pair where they're almost never emphasis:
    /// `*` at the start of a line is a list bullet, and `*`/`_` right after
    /// a word character is multiplication or snake_case.
    private func shouldAutoPairSymmetric(_ char: Character, at location: Int) -> Bool {
        guard char == "*" || char == "_" else { return true }
        let nsString = self.string as NSString

        if char == "*", onlyWhitespacePrecedesOnLine(location: location, in: nsString) {
            return false
        }

        if location > 0,
            let scalar = UnicodeScalar(nsString.character(at: location - 1)),
            CharacterSet.alphanumerics.contains(scalar)
        {
            return false
        }

        return true
    }

    private func onlyWhitespacePrecedesOnLine(location: Int, in nsString: NSString) -> Bool {
        var index = location - 1
        while index >= 0 {
            let char = nsString.character(at: index)
            if char == 0x0A { return true }
            if char != 0x20 && char != 0x09 { return false }
            index -= 1
        }
        return true
    }

    private func shouldSkipOver(char: Character, at location: Int) -> Bool {
        let nsString = (self.string as NSString)
        guard location < nsString.length,
            let scalar = UnicodeScalar(nsString.character(at: location))
        else {
            return false
        }
        let nextChar = Character(scalar)
        return nextChar == char
    }

    private func moveCursorRight() {
        let range = self.selectedRange()
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
    }

    // MARK: - Markdown Formatting

    @objc func toggleBold(_ sender: Any?) {
        toggleInlineMarker("**")
    }

    @objc func toggleItalic(_ sender: Any?) {
        toggleInlineMarker("*")
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        toggleInlineMarker("`")
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        toggleInlineMarker("~~")
    }

    /// Inserts `[text](url)` markdown. The selection becomes the link text;
    /// a URL on the clipboard is used directly, otherwise a placeholder is
    /// left selected so typing replaces it.
    @objc func insertLinkMarkup(_ sender: Any?) {
        let range = selectedRange()
        let nsString = self.string as NSString
        let selectedText = range.length > 0 ? nsString.substring(with: range) : ""

        let clipboardURL = NSPasteboard.general.string(forType: .string).flatMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let isURL =
                (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
                && !trimmed.contains(where: \.isWhitespace)
            return isURL ? trimmed : nil
        }

        let text = selectedText.isEmpty ? "text" : selectedText
        let url = clipboardURL ?? "url"
        let markup = "[\(text)](\(url))"

        // Select whichever placeholder still needs typing.
        let selection: NSRange
        if clipboardURL == nil {
            let urlOffset = ("[\(text)](" as NSString).length
            selection = NSRange(location: range.location + urlOffset, length: ("url" as NSString).length)
        } else if selectedText.isEmpty {
            selection = NSRange(location: range.location + 1, length: ("text" as NSString).length)
        } else {
            selection = NSRange(location: range.location + (markup as NSString).length, length: 0)
        }

        replaceForFormatting(range, with: markup, select: selection)
    }

    /// Inserts Hugo's manual summary divider on its own line.
    @objc func insertSummaryDivider(_ sender: Any?) {
        let range = selectedRange()
        let nsString = self.string as NSString
        let atLineStart = range.location == 0 || nsString.character(at: range.location - 1) == 0x0A
        let insertion = (atLineStart ? "" : "\n") + "<!--more-->\n"
        replaceForFormatting(
            range,
            with: insertion,
            select: NSRange(location: range.location + (insertion as NSString).length, length: 0)
        )
    }

    /// Wraps the selection in `marker`, or removes the markers when the
    /// selection (or its immediate surroundings) already carries them. With
    /// no selection, inserts an empty pair and puts the cursor inside.
    func toggleInlineMarker(_ marker: String) {
        let range = selectedRange()
        let nsString = self.string as NSString
        let markerLength = (marker as NSString).length

        guard range.length > 0 else {
            replaceForFormatting(
                range,
                with: marker + marker,
                select: NSRange(location: range.location + markerLength, length: 0)
            )
            return
        }

        let selectedText = nsString.substring(with: range)

        // Markers inside the selection: **bold** selected whole.
        if selectedText.hasPrefix(marker), selectedText.hasSuffix(marker),
            range.length >= markerLength * 2
        {
            let inner = (selectedText as NSString).substring(
                with: NSRange(location: markerLength, length: range.length - markerLength * 2)
            )
            replaceForFormatting(
                range,
                with: inner,
                select: NSRange(location: range.location, length: (inner as NSString).length)
            )
            return
        }

        // Markers just outside the selection: bold selected inside **…**.
        let before = NSRange(location: range.location - markerLength, length: markerLength)
        let after = NSRange(location: NSMaxRange(range), length: markerLength)
        if before.location >= 0, NSMaxRange(after) <= nsString.length,
            nsString.substring(with: before) == marker,
            nsString.substring(with: after) == marker
        {
            let full = NSRange(location: before.location, length: markerLength * 2 + range.length)
            replaceForFormatting(
                full,
                with: selectedText,
                select: NSRange(location: before.location, length: range.length)
            )
            return
        }

        replaceForFormatting(
            range,
            with: marker + selectedText + marker,
            select: NSRange(location: range.location + markerLength, length: range.length)
        )
    }

    /// Inserts an internal link as `[text]({{< relref "path" >}})`. The
    /// selection becomes the link text; otherwise `fallbackText` is used
    /// and left selected for editing.
    func insertPostLink(relrefPath: String, fallbackText: String) {
        let range = selectedRange()
        let nsString = self.string as NSString
        let selectedText = range.length > 0 ? nsString.substring(with: range) : ""
        let text = selectedText.isEmpty ? fallbackText : selectedText
        let markup = "[\(text)]({{< relref \"\(relrefPath)\" >}})"

        let selection: NSRange
        if selectedText.isEmpty {
            selection = NSRange(location: range.location + 1, length: (text as NSString).length)
        } else {
            selection = NSRange(location: range.location + (markup as NSString).length, length: 0)
        }

        replaceForFormatting(range, with: markup, select: selection)
    }

    /// Inserts a shortcode template at the cursor, selecting its
    /// placeholder so typing fills the main argument.
    func insertShortcodeTemplate(_ shortcode: ShortcodeTemplate) {
        let range = selectedRange()
        let template = shortcode.template
        let templateNS = template as NSString

        let selection: NSRange
        if let placeholder = shortcode.selectionPlaceholder {
            let placeholderRange = templateNS.range(of: placeholder)
            if placeholderRange.location != NSNotFound {
                selection = NSRange(
                    location: range.location + placeholderRange.location,
                    length: placeholderRange.length
                )
            } else {
                selection = NSRange(location: range.location + templateNS.length, length: 0)
            }
        } else {
            selection = NSRange(location: range.location + templateNS.length, length: 0)
        }

        replaceForFormatting(range, with: template, select: selection)
    }

    private func replaceForFormatting(_ range: NSRange, with newText: String, select selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: newText) else { return }
        replaceCharacters(in: range, with: newText)
        didChangeText()
        setSelectedRange(selection)
    }

    // MARK: - Custom Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBlockquoteBorders(in: dirtyRect)
        drawRenderedImages(in: dirtyRect)
        drawImagePasteIndicator(in: dirtyRect)
    }

    private func startSpinnerTimer() {
        guard spinnerTimer == nil else { return }
        // ~30 fps is smooth enough for a simple spinner and cheap on CPU
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.needsDisplay = true
        }
    }

    private func stopSpinnerTimer() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
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
            let textContainer = textContainer
        else { return }

        let borderWidth: CGFloat = 3
        let borderInset: CGFloat = 16  // matches the paragraph indent step

        // Find visible character range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: dirtyRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        textStorage.enumerateAttribute(.blockquoteInfo, in: visibleCharRange, options: []) { value, range, _ in
            guard let info = value as? BlockquoteInfo else { return }

            // Get the line fragment rects for this blockquote range
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
                lineRect, usedRect, container, lineGlyphRange, stop in
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
            let textContainer = textContainer
        else { return }

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
            let image = NSImage(data: pngData)
        {
            return image
        }

        // Try TIFF (common for screenshots)
        if let tiffData = pasteboard.data(forType: .tiff),
            let image = NSImage(data: tiffData)
        {
            return image
        }

        // Try file URLs pointing to images
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: ["public.image"],
            ]) as? [URL], let url = urls.first
        {
            return NSImage(contentsOf: url)
        }

        return nil
    }

    private func handleImagePaste(_ image: NSImage) {
        guard !isPastingImage else { return }

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

        let outputFormat = ImagePasteFormat.current()
        let namingStrategy = ImagePasteNamingStrategy.current()
        let maxDimension = UserDefaults.standard.object(forKey: DefaultsKey.imagePasteMaxDimension) as? Double ?? 0
        let jpegQuality = UserDefaults.standard.object(forKey: DefaultsKey.imagePasteJPEGQuality) as? Double ?? 0.85

        let filename = generateImageFilename(
            strategy: namingStrategy,
            context: context,
            fileExtension: outputFormat.fileExtension
        )
        let location = ImagePasteLocation.current(siteURL: context.siteURL)
        let destination: ImagePasteDestination
        do {
            destination = try ImagePasteDestinationAllocator.validatedDestination(
                context: context,
                location: location,
                filename: filename
            )
        } catch {
            isPastingImage = false
            needsDisplay = true
            let alert = NSAlert()
            alert.messageText = "Failed to save image"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            return
        }
        let insertionRange = selectedRange()
        let pasteRevision = contentRevision
        let pastePostURL = context.postURL.standardizedFileURL

        guard let tiffData = image.tiffRepresentation else {
            isPastingImage = false
            needsDisplay = true
            let alert = NSAlert()
            alert.messageText = "Failed to save image"
            alert.informativeText = "Could not encode image data for save."
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try FileManager.default.createDirectory(
                    at: destination.saveURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                guard
                    let encodedData = self?.encodeImageData(
                        from: tiffData,
                        format: outputFormat,
                        maxDimension: maxDimension,
                        jpegQuality: jpegQuality
                    )
                else {
                    throw CocoaError(.fileWriteUnknown)
                }

                guard FileManager.default.createFile(atPath: destination.saveURL.path, contents: encodedData) else {
                    throw CocoaError(.fileWriteFileExists)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        Self.removePastedFile(at: destination.saveURL)
                        return
                    }
                    self.isPastingImage = false
                    self.needsDisplay = true
                    guard self.canCompleteImagePaste(revision: pasteRevision, postURL: pastePostURL) else {
                        Self.removePastedFile(at: destination.saveURL)
                        return
                    }

                    let maxLocation = self.string.utf16.count
                    let safeRange = NSRange(location: min(insertionRange.location, maxLocation), length: 0)
                    let (markdown, altRange) = Self.imageMarkdown(forPath: destination.markdownPath)
                    self.insertText(markdown, replacementRange: safeRange)
                    // Leave the alt text selected so typing replaces it —
                    // an empty alt hurts accessibility and is easy to forget.
                    self.setSelectedRange(
                        NSRange(location: safeRange.location + altRange.location, length: altRange.length)
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isPastingImage = false
                    self.needsDisplay = true
                    let alert = NSAlert()
                    alert.messageText = "Failed to save image"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }

    private static func removePastedFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("Failed to remove cancelled pasted image: \(error.localizedDescription)")
        }
    }

    /// Builds the markdown for a pasted image with a default alt text
    /// derived from the file name, returning the alt's range within the
    /// markdown so callers can preselect it.
    static func imageMarkdown(forPath path: String) -> (markdown: String, altRange: NSRange) {
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let alt =
            stem
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let markdown = "![\(alt)](\(path))"
        return (markdown, NSRange(location: 2, length: (alt as NSString).length))
    }

    private static let imageTimestampFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()

    private func generateImageFilename(
        strategy: ImagePasteNamingStrategy,
        context: ImageContext,
        fileExtension: String
    ) -> String {
        let timestamp = Self.imageTimestampFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "")
        switch strategy {
        case .timestamp:
            return "image-\(timestamp).\(fileExtension)"
        case .uuid:
            return "image-\(UUID().uuidString.lowercased()).\(fileExtension)"
        case .postSlugTimestamp:
            let postSlug = context.postURL.deletingPathExtension().lastPathComponent
            return "\(postSlug)-\(timestamp).\(fileExtension)"
        }
    }

    private func encodeImageData(
        from tiffData: Data,
        format: ImagePasteFormat,
        maxDimension: Double,
        jpegQuality: Double
    ) -> Data? {
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let scaledBitmap = scaledBitmapRep(bitmap, maxDimension: maxDimension) ?? bitmap
        switch format {
        case .png:
            return scaledBitmap.representation(using: .png, properties: [:])
        case .jpeg:
            let quality = min(max(jpegQuality, 0.1), 1.0)
            return scaledBitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }

    private func scaledBitmapRep(_ source: NSBitmapImageRep, maxDimension: Double) -> NSBitmapImageRep? {
        guard maxDimension > 0 else { return source }

        let sourceWidth = CGFloat(source.pixelsWide)
        let sourceHeight = CGFloat(source.pixelsHigh)
        let longestEdge = max(sourceWidth, sourceHeight)
        guard longestEdge > CGFloat(maxDimension) else { return source }

        let scale = CGFloat(maxDimension) / longestEdge
        let targetSize = NSSize(
            width: max(1, floor(sourceWidth * scale)),
            height: max(1, floor(sourceHeight * scale))
        )

        let sourceImage = NSImage(size: NSSize(width: sourceWidth, height: sourceHeight))
        sourceImage.addRepresentation(source)

        let targetImage = NSImage(size: targetSize)
        targetImage.lockFocus()
        sourceImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceHeight)),
            operation: .copy,
            fraction: 1.0
        )
        targetImage.unlockFocus()

        guard let targetTIFF = targetImage.tiffRepresentation,
            let targetBitmap = NSBitmapImageRep(data: targetTIFF)
        else {
            return nil
        }

        return targetBitmap
    }

}
