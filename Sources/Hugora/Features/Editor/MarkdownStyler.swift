import AppKit
import Foundation
import Markdown

// MARK: - Constants

private enum Constants {
    static let minimumFontSize: CGFloat = 0.01
    static let blockquoteIndentation: CGFloat = 20
    static let imagePadding: CGFloat = 12
    static let maxImageWidth: CGFloat = 600
}

// MARK: - Theme

struct Theme {
    struct HeadingStyle {
        let font: NSFont
        let color: NSColor
    }

    let baseFont: NSFont
    let baseColor: NSColor
    let headings: [HeadingStyle]  // Index 0 = h1, ... 5 = h6
    let boldColor: NSColor
    let italicColor: NSColor
    let inlineCodeFont: NSFont
    let inlineCodeColor: NSColor
    let inlineCodeBackground: NSColor
    let linkColor: NSColor
    let blockquoteColor: NSColor
    let blockquoteBorderColor: NSColor
    let codeBlockFont: NSFont
    let codeBlockColor: NSColor
    let codeBlockBackground: NSColor
    let tableFont: NSFont
    let tableBackground: NSColor
    let tableHeaderBackground: NSColor
    let tableBorderColor: NSColor
    let frontmatterFont: NSFont
    let frontmatterColor: NSColor
    let frontmatterBackground: NSColor
    let frontmatterKeyColor: NSColor

    func headingStyle(level: Int) -> HeadingStyle {
        let index = max(0, min(level - 1, headings.count - 1))
        return headings[index]
    }
}

// MARK: - Custom Attribute Keys

extension NSAttributedString.Key {
    static let renderedImage = NSAttributedString.Key("com.hugora.renderedImage")
    static let blockquoteInfo = NSAttributedString.Key("com.hugora.blockquoteInfo")
}

/// Information about a blockquote for custom border drawing
struct BlockquoteInfo {
    let nestingLevel: Int  // 1 = top-level, 2 = nested once, etc.
    let borderColor: NSColor
}

/// Information about a rendered image for custom drawing
struct RenderedImageInfo {
    let image: NSImage
    let altText: String
    let originalSize: NSSize
}

// MARK: - MarkdownStyler

struct MarkdownStyler {
    let theme: Theme

    init(theme: Theme = .defaultLight) {
        self.theme = theme
    }

    /// Applies markdown styling to text storage within a visible range.
    ///
    /// Convenience wrapper that extracts text from storage and delegates to the
    /// full `style()` method. Resets base attributes, applies element-specific
    /// styles, hides syntax markers when cursor is outside their elements,
    /// and renders images inline when appropriate.
    ///
    /// - Parameters:
    ///   - textStorage: The text storage to apply styles to.
    ///   - visibleRange: The range of text to style (for performance).
    ///   - document: The parsed markdown document.
    ///   - cursorPosition: Optional cursor position for syntax hiding behavior.
    ///   - imageContext: Optional context for resolving image paths.
    /// - Returns: A cache of styled elements for efficient cursor-only updates.
    @discardableResult
    func applyStyles(to textStorage: NSTextStorage, in visibleRange: NSRange, document: Document, cursorPosition: Int? = nil, imageContext: ImageContext? = nil) -> StylePassCache {
        let text = textStorage.string
        return style(text: text, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: cursorPosition, imageContext: imageContext)
    }

    @discardableResult
    func style(
        text: String,
        document: Document,
        textStorage: NSTextStorage,
        visibleRange: NSRange,
        cursorPosition: Int? = nil,
        theme: Theme? = nil,
        imageContext: ImageContext? = nil
    ) -> StylePassCache {
        let activeTheme = theme ?? self.theme
        let preferences = EditorPreferences.current()
        let fontScale = preferences.fontScale(for: activeTheme)

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        resetBaseAttributes(
            textStorage: textStorage,
            range: visibleRange,
            theme: activeTheme,
            fontScale: fontScale,
            lineSpacing: preferences.lineSpacing
        )

        // Detect and style frontmatter first
        let frontmatter = detectFrontmatter(in: text)
        var allMarkers: [SyntaxMarker] = []
        var imageSpans: [(range: NSRange, source: String?, altText: String)] = []

        if let fm = frontmatter {
            applyFrontmatterStyle(
                range: fm.range,
                textStorage: textStorage,
                theme: activeTheme,
                fontScale: fontScale,
                format: fm.format
            )

            // Add delimiter markers for hiding
            allMarkers.append(SyntaxMarker(range: fm.openingDelimiterRange, parentRange: fm.range, parentKind: .frontmatter))
            allMarkers.append(SyntaxMarker(range: fm.closingDelimiterRange, parentRange: fm.range, parentKind: .frontmatter))
        }

        var collector = StyleCollector()
        collector.visit(document)

        for span in collector.spans {
            guard let nsRange = convertRange(span.sourceRange, in: text) else { continue }

            // Skip spans inside frontmatter
            if let fm = frontmatter, NSIntersectionRange(nsRange, fm.range).length > 0 {
                continue
            }

            let intersection = NSIntersectionRange(nsRange, visibleRange)
            guard intersection.length > 0 else { continue }

            // Collect image spans for special handling
            if case .image(let source, let altText) = span.kind {
                imageSpans.append((range: nsRange, source: source, altText: altText))
            }

            applyStyle(
                kind: span.kind,
                range: nsRange,
                textStorage: textStorage,
                theme: activeTheme,
                fontScale: fontScale,
                lineSpacing: preferences.lineSpacing
            )

            // Collect syntax markers for hiding
            let markers = SyntaxMarkerCalculator.markers(for: span, in: text)
            allMarkers.append(contentsOf: markers)
        }

        // Apply syntax hiding based on cursor position
        applySyntaxHiding(
            markers: allMarkers,
            cursorPosition: cursorPosition,
            textStorage: textStorage,
            visibleRange: visibleRange
        )

        // Apply image rendering (after syntax hiding so we can add attachments)
        if let context = imageContext {
            applyImageRendering(
                imageSpans: imageSpans,
                cursorPosition: cursorPosition,
                textStorage: textStorage,
                imageContext: context,
                theme: activeTheme,
                fontScale: fontScale,
                lineSpacing: preferences.lineSpacing
            )
        }

        return StylePassCache(
            markers: allMarkers,
            imageSpans: imageSpans,
            fontScale: fontScale,
            lineSpacing: preferences.lineSpacing
        )
    }

    /// Lightweight cursor-only update: only re-applies syntax hiding and image rendering
    /// for markers whose visibility changed between oldCursor and newCursor.
    func updateCursorStyles(
        in textStorage: NSTextStorage,
        cache: StylePassCache,
        oldCursor: Int,
        newCursor: Int,
        imageContext: ImageContext?
    ) {
        let activeTheme = theme

        // Update syntax markers that changed state
        for marker in cache.markers {
            let wasInside = oldCursor >= marker.parentRange.location && oldCursor <= NSMaxRange(marker.parentRange)
            let nowInside = newCursor >= marker.parentRange.location && newCursor <= NSMaxRange(marker.parentRange)
            guard wasInside != nowInside else { continue }

            let clampedRange = NSIntersectionRange(marker.range, NSRange(location: 0, length: textStorage.length))
            guard clampedRange.length > 0 else { continue }

            if nowInside {
                // Entering element: restore base attributes + parent style on marker range
                resetBaseAttributes(
                    textStorage: textStorage,
                    range: clampedRange,
                    theme: activeTheme,
                    fontScale: cache.fontScale,
                    lineSpacing: cache.lineSpacing
                )
                applyStyle(
                    kind: marker.parentKind,
                    range: clampedRange,
                    textStorage: textStorage,
                    theme: activeTheme,
                    fontScale: cache.fontScale,
                    lineSpacing: cache.lineSpacing
                )
            } else {
                // Leaving element: apply hiding attributes
                if marker.preserveLineHeight {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
                } else {
                    let hiddenFont = NSFont.systemFont(ofSize: Constants.minimumFontSize)
                    textStorage.addAttribute(.font, value: hiddenFont, range: clampedRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
                }
            }
        }

        // Update image spans that changed state
        guard let context = imageContext else { return }
        for imageSpan in cache.imageSpans {
            let range = imageSpan.range
            guard range.length > 0, range.location + range.length <= textStorage.length else { continue }

            let wasInside = oldCursor >= range.location && oldCursor <= NSMaxRange(range)
            let nowInside = newCursor >= range.location && newCursor <= NSMaxRange(range)
            guard wasInside != nowInside else { continue }

            if nowInside {
                // Entering image: show raw markdown
                textStorage.removeAttribute(.attachment, range: range)
                textStorage.removeAttribute(.renderedImage, range: range)
                // Restore base + image style
                resetBaseAttributes(
                    textStorage: textStorage,
                    range: range,
                    theme: activeTheme,
                    fontScale: cache.fontScale,
                    lineSpacing: cache.lineSpacing
                )
                applyStyle(
                    kind: .image(source: imageSpan.source, altText: imageSpan.altText),
                    range: range,
                    textStorage: textStorage,
                    theme: activeTheme,
                    fontScale: cache.fontScale,
                    lineSpacing: cache.lineSpacing
                )
            } else {
                // Leaving image: render it (reuse existing logic for single span)
                applyImageRendering(
                    imageSpans: [imageSpan],
                    cursorPosition: newCursor,
                    textStorage: textStorage,
                    imageContext: context,
                    theme: activeTheme,
                    fontScale: cache.fontScale,
                    lineSpacing: cache.lineSpacing
                )
            }
        }
    }

    private func applyFrontmatterStyle(
        range: NSRange,
        textStorage: NSTextStorage,
        theme: Theme,
        fontScale: CGFloat,
        format: FrontmatterFormat
    ) {
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard clampedRange.length > 0 else { return }

        let font = scaledFont(theme.frontmatterFont, scale: fontScale)
        textStorage.addAttribute(.font, value: font, range: clampedRange)
        textStorage.addAttribute(.foregroundColor, value: theme.frontmatterColor, range: clampedRange)
        textStorage.addAttribute(.backgroundColor, value: theme.frontmatterBackground, range: clampedRange)

        // Highlight front matter keys.
        let nsString = textStorage.string as NSString
        let content = nsString.substring(with: clampedRange)
        let lines = content.components(separatedBy: .newlines)
        var offset = clampedRange.location

        for line in lines {
            let keyLength: Int?
            switch format {
            case .yaml, .json:
                if let colonIdx = line.firstIndex(of: ":"), colonIdx != line.startIndex {
                    keyLength = line.distance(from: line.startIndex, to: colonIdx)
                } else {
                    keyLength = nil
                }
            case .toml:
                if let equalsIdx = line.firstIndex(of: "="), equalsIdx != line.startIndex {
                    keyLength = line.distance(from: line.startIndex, to: equalsIdx)
                } else {
                    keyLength = nil
                }
            }

            if let keyLength, keyLength > 0 {
                let keyRange = NSRange(location: offset, length: keyLength)
                textStorage.addAttribute(
                    .foregroundColor,
                    value: theme.frontmatterKeyColor,
                    range: keyRange
                )
            }
            offset += line.utf16.count + 1  // +1 for newline
        }
    }

    /// Hides syntax markers when cursor is not within their parent element.
    private func applySyntaxHiding(
        markers: [SyntaxMarker],
        cursorPosition: Int?,
        textStorage: NSTextStorage,
        visibleRange: NSRange
    ) {
        for marker in markers {
            let markerIntersection = NSIntersectionRange(marker.range, visibleRange)
            guard markerIntersection.length > 0 else { continue }

            // Check if cursor is within the parent element range
            let cursorInElement: Bool
            if let cursor = cursorPosition {
                cursorInElement = cursor >= marker.parentRange.location && cursor <= NSMaxRange(marker.parentRange)
            } else {
                cursorInElement = false
            }

            guard !cursorInElement else { continue }

            // Hide syntax: make it nearly invisible
            let clampedRange = NSIntersectionRange(marker.range, NSRange(location: 0, length: textStorage.length))
            guard clampedRange.length > 0 else { continue }

            if marker.preserveLineHeight {
                // For empty blockquote lines: hide color only, keep font to preserve line height
                textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
            } else {
                // Normal hiding: tiny font to collapse space while maintaining string integrity
                let hiddenFont = NSFont.systemFont(ofSize: Constants.minimumFontSize)
                textStorage.addAttribute(.font, value: hiddenFont, range: clampedRange)
                textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
            }
        }
    }

    private func resetBaseAttributes(
        textStorage: NSTextStorage,
        range: NSRange,
        theme: Theme,
        fontScale: CGFloat,
        lineSpacing: CGFloat
    ) {
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard clampedRange.length > 0 else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = lineSpacing

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: scaledFont(theme.baseFont, scale: fontScale),
            .foregroundColor: theme.baseColor,
            .backgroundColor: NSColor.clear,
            .underlineStyle: 0,
            .paragraphStyle: paragraphStyle
        ]
        textStorage.setAttributes(baseAttributes, range: clampedRange)
    }

    private func applyStyle(
        kind: StyleKind,
        range: NSRange,
        textStorage: NSTextStorage,
        theme: Theme,
        fontScale: CGFloat,
        lineSpacing: CGFloat
    ) {
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard clampedRange.length > 0 else { return }

        switch kind {
        case .heading(let level):
            let style = theme.headingStyle(level: level)
            let font = scaledFont(style.font, scale: fontScale)
            textStorage.addAttribute(.font, value: font, range: clampedRange)
            textStorage.addAttribute(.foregroundColor, value: style.color, range: clampedRange)

        case .bold:
            applyFontTrait(.boldFontMask, range: clampedRange, textStorage: textStorage)
            textStorage.addAttribute(.foregroundColor, value: theme.boldColor, range: clampedRange)

        case .italic:
            applyFontTrait(.italicFontMask, range: clampedRange, textStorage: textStorage)
            textStorage.addAttribute(.foregroundColor, value: theme.italicColor, range: clampedRange)

        case .inlineCode:
            let font = scaledFont(theme.inlineCodeFont, scale: fontScale)
            textStorage.addAttribute(.font, value: font, range: clampedRange)
            textStorage.addAttribute(.foregroundColor, value: theme.inlineCodeColor, range: clampedRange)
            textStorage.addAttribute(.backgroundColor, value: theme.inlineCodeBackground, range: clampedRange)

        case .link:
            textStorage.addAttribute(.foregroundColor, value: theme.linkColor, range: clampedRange)
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: clampedRange)

        case .blockquote(let nestingLevel):
            // Apply blockquote styling: muted color, italic, and custom attribute for border drawing
            textStorage.addAttribute(.foregroundColor, value: theme.blockquoteColor, range: clampedRange)
            applyFontTrait(.italicFontMask, range: clampedRange, textStorage: textStorage)

            // Store blockquote info for custom border drawing (includes border color for EditorTextView)
            let info = BlockquoteInfo(nestingLevel: nestingLevel, borderColor: theme.blockquoteBorderColor)
            textStorage.addAttribute(.blockquoteInfo, value: info, range: clampedRange)

            // Apply paragraph style with left indent for the nesting level
            let indent: CGFloat = CGFloat(nestingLevel) * Constants.blockquoteIndentation
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = indent
            paragraphStyle.firstLineHeadIndent = indent
            paragraphStyle.lineHeightMultiple = lineSpacing
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: clampedRange)

        case .codeBlock:
            let font = scaledFont(theme.codeBlockFont, scale: fontScale)
            textStorage.addAttribute(.font, value: font, range: clampedRange)
            textStorage.addAttribute(.foregroundColor, value: theme.codeBlockColor, range: clampedRange)
            textStorage.addAttribute(.backgroundColor, value: theme.codeBlockBackground, range: clampedRange)

        case .table:
            let font = scaledFont(theme.tableFont, scale: fontScale)
            textStorage.addAttribute(.font, value: font, range: clampedRange)
            textStorage.addAttribute(.backgroundColor, value: theme.tableBackground, range: clampedRange)

        case .tableHeader:
            applyFontTrait(.boldFontMask, range: clampedRange, textStorage: textStorage)
            textStorage.addAttribute(.backgroundColor, value: theme.tableHeaderBackground, range: clampedRange)

        case .tableCell:
            break

        case .frontmatter:
            // Frontmatter styled separately via applyFrontmatterStyle
            break

        case .image:
            // Base styling for image markdown (actual rendering happens in applyImageRendering)
            textStorage.addAttribute(.foregroundColor, value: theme.linkColor, range: clampedRange)
        }
    }

    /// Helper to fall back to showing markdown for an image span.
    private func fallbackToMarkdown(
        _ imageSpan: (range: NSRange, source: String?, altText: String),
        range: NSRange,
        textStorage: NSTextStorage,
        theme: Theme,
        fontScale: CGFloat,
        lineSpacing: CGFloat
    ) {
        showImageMarkdown(
            range: range,
            source: imageSpan.source,
            altText: imageSpan.altText,
            textStorage: textStorage,
            theme: theme,
            fontScale: fontScale,
            lineSpacing: lineSpacing
        )
    }

    /// Renders images inline when cursor is not within the image markdown.
    private func applyImageRendering(
        imageSpans: [(range: NSRange, source: String?, altText: String)],
        cursorPosition: Int?,
        textStorage: NSTextStorage,
        imageContext: ImageContext,
        theme: Theme,
        fontScale: CGFloat,
        lineSpacing: CGFloat
    ) {
        for imageSpan in imageSpans {
            let range = imageSpan.range
            guard range.length > 0, range.location + range.length <= textStorage.length else {
                continue
            }

            // Check if cursor is within this image element
            let cursorInImage: Bool
            if let cursor = cursorPosition {
                cursorInImage = cursor >= range.location && cursor <= NSMaxRange(range)
            } else {
                cursorInImage = false
            }

            if cursorInImage {
                fallbackToMarkdown(imageSpan, range: range, textStorage: textStorage, theme: theme, fontScale: fontScale, lineSpacing: lineSpacing)
                continue
            }

            // Cursor outside: load and display image
            guard let source = imageSpan.source,
                  let imageURL = imageContext.resolveImagePath(source) else {
                fallbackToMarkdown(imageSpan, range: range, textStorage: textStorage, theme: theme, fontScale: fontScale, lineSpacing: lineSpacing)
                continue
            }

            guard imageURL.isFileURL else {
                fallbackToMarkdown(imageSpan, range: range, textStorage: textStorage, theme: theme, fontScale: fontScale, lineSpacing: lineSpacing)
                continue
            }

            // Try to load image (from cache or file)
            let image: NSImage?
            if let cached = ImageCache.shared.image(for: imageURL) {
                image = cached
            } else {
                image = loadLocalImage(from: imageURL)
            }

            guard let nsImage = image else {
                fallbackToMarkdown(imageSpan, range: range, textStorage: textStorage, theme: theme, fontScale: fontScale, lineSpacing: lineSpacing)
                continue
            }

            // Store image info as custom attribute for later rendering
            // NSTextAttachment only works with the U+FFFC character, not arbitrary text
            // We'll use custom drawing in EditorTextView instead
            let maxWidth: CGFloat = Constants.maxImageWidth
            let originalSize = nsImage.size
            var targetHeight = originalSize.height
            if originalSize.width > maxWidth {
                let scale = maxWidth / originalSize.width
                targetHeight = originalSize.height * scale
            }

            let imageInfo = RenderedImageInfo(image: nsImage, altText: imageSpan.altText, originalSize: nsImage.size)
            textStorage.addAttribute(.renderedImage, value: imageInfo, range: range)

            // Add paragraph spacing after this line to make room for the image
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacingBefore = 0
            paragraphStyle.paragraphSpacing = targetHeight + Constants.imagePadding
            paragraphStyle.lineHeightMultiple = lineSpacing
            textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    }

    private func showImageMarkdown(
        range: NSRange,
        source: String?,
        altText: String,
        textStorage: NSTextStorage,
        theme: Theme,
        fontScale: CGFloat,
        lineSpacing: CGFloat
    ) {
        textStorage.removeAttribute(.renderedImage, range: range)
        resetBaseAttributes(
            textStorage: textStorage,
            range: range,
            theme: theme,
            fontScale: fontScale,
            lineSpacing: lineSpacing
        )
        applyStyle(
            kind: .image(source: source, altText: altText),
            range: range,
            textStorage: textStorage,
            theme: theme,
            fontScale: fontScale,
            lineSpacing: lineSpacing
        )
    }

    /// Loads a local image file and caches it.
    private func loadLocalImage(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        ImageCache.shared.setImage(image, for: url)
        return image
    }

    /// Derives font with added traits from existing font runs to handle nested markup.
    private func applyFontTrait(
        _ trait: NSFontTraitMask,
        range: NSRange,
        textStorage: NSTextStorage
    ) {
        let fontManager = NSFontManager.shared

        textStorage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let existingFont = value as? NSFont else { return }

            let newFont = fontManager.convert(existingFont, toHaveTrait: trait)
            textStorage.addAttribute(.font, value: newFont, range: subrange)
        }
    }

    private func scaledFont(_ font: NSFont, scale: CGFloat) -> NSFont {
        let newSize = max(font.pointSize * scale, 1)
        guard let scaled = NSFont(descriptor: font.fontDescriptor, size: newSize) else { return font }
        return scaled
    }
}

// MARK: - Editor Preferences

private struct EditorPreferences {
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    static func current() -> EditorPreferences {
        let defaults = UserDefaults.standard
        let storedFontSize = defaults.object(forKey: DefaultsKey.editorFontSize) as? Double ?? 16
        let storedLineSpacing = defaults.object(forKey: DefaultsKey.editorLineSpacing) as? Double ?? 1.4
        return EditorPreferences(
            fontSize: CGFloat(max(storedFontSize, 1)),
            lineSpacing: CGFloat(max(storedLineSpacing, 1))
        )
    }

    func fontScale(for theme: Theme) -> CGFloat {
        let baseSize = max(theme.baseFont.pointSize, 1)
        return fontSize / baseSize
    }
}
