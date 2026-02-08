import AppKit
import Foundation
import Markdown

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

    static var `default`: Theme {
        let baseSize: CGFloat = 16
        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: .textColor,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: .textColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: .textColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: .textColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: .textColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: .secondaryLabelColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.9, weight: .medium), color: .secondaryLabelColor),
            ],
            boldColor: .textColor,
            italicColor: .textColor,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            inlineCodeColor: .systemPink,
            inlineCodeBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.3),
            linkColor: .linkColor,
            blockquoteColor: .secondaryLabelColor,
            blockquoteBorderColor: .systemOrange,
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            codeBlockColor: .textColor,
            codeBlockBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.2),
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            tableBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.1),
            tableHeaderBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.25),
            tableBorderColor: .separatorColor,
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: .secondaryLabelColor,
            frontmatterBackground: NSColor.quaternaryLabelColor.withAlphaComponent(0.15),
            frontmatterKeyColor: .systemTeal
        )
    }

    func headingStyle(level: Int) -> HeadingStyle {
        let index = max(0, min(level - 1, headings.count - 1))
        return headings[index]
    }
}

// MARK: - StyleSpan

enum StyleKind {
    case heading(level: Int)
    case bold
    case italic
    case inlineCode
    case link
    case blockquote(nestingLevel: Int)
    case codeBlock
    case table
    case tableHeader
    case tableCell
    case frontmatter
    case image(source: String?, altText: String)
}

// MARK: - Frontmatter Detection

struct FrontmatterRange {
    let range: NSRange
    let openingDelimiterRange: NSRange
    let closingDelimiterRange: NSRange
}

func detectFrontmatter(in text: String) -> FrontmatterRange? {
    let nsString = text as NSString
    guard nsString.length >= 7 else { return nil }  // minimum: "---\n---"
    
    // Must start with ---
    guard nsString.substring(with: NSRange(location: 0, length: 3)) == "---" else { return nil }
    
    // Find end of first line (opening delimiter)
    var openEnd = 3
    while openEnd < nsString.length {
        let char = nsString.character(at: openEnd)
        if char == 0x0A || char == 0x0D { // \n or \r
            openEnd += 1
            // Handle \r\n
            if char == 0x0D && openEnd < nsString.length && nsString.character(at: openEnd) == 0x0A {
                openEnd += 1
            }
            break
        }
        openEnd += 1
    }
    
    // Find closing ---
    let searchStart = openEnd
    let remaining = nsString.substring(from: searchStart)
    
    // Look for \n--- at start of a line
    var closeStart: Int? = nil
    var pos = 0
    let remainingNS = remaining as NSString
    
    while pos < remainingNS.length {
        // Check if we're at start of line with ---
        if remainingNS.substring(from: pos).hasPrefix("---") {
            // Verify it's start of line (pos == 0 or preceded by newline)
            if pos == 0 || remainingNS.character(at: pos - 1) == 0x0A || remainingNS.character(at: pos - 1) == 0x0D {
                closeStart = searchStart + pos
                break
            }
        }
        pos += 1
    }
    
    guard let closeLocation = closeStart else { return nil }
    
    // Find end of closing delimiter line
    var closeEnd = closeLocation + 3
    while closeEnd < nsString.length {
        let char = nsString.character(at: closeEnd)
        if char == 0x0A || char == 0x0D {
            closeEnd += 1
            if char == 0x0D && closeEnd < nsString.length && nsString.character(at: closeEnd) == 0x0A {
                closeEnd += 1
            }
            break
        }
        closeEnd += 1
    }
    
    let fullRange = NSRange(location: 0, length: closeEnd)
    let openRange = NSRange(location: 0, length: openEnd)
    let closingRange = NSRange(location: closeLocation, length: closeEnd - closeLocation)
    
    return FrontmatterRange(range: fullRange, openingDelimiterRange: openRange, closingDelimiterRange: closingRange)
}

struct StyleSpan {
    let sourceRange: SourceRange
    let kind: StyleKind
}

// MARK: - SyntaxMarker

/// Represents syntax characters to hide (e.g., `**`, `#`, backticks).
struct SyntaxMarker {
    let range: NSRange         // Range of the syntax characters to hide
    let parentRange: NSRange   // Full range of the containing element (for cursor detection)
    let parentKind: StyleKind  // Kind of the parent element (for restoring styles)
    let preserveLineHeight: Bool  // If true, only hide color (don't shrink font) to preserve line height

    init(range: NSRange, parentRange: NSRange, parentKind: StyleKind, preserveLineHeight: Bool = false) {
        self.range = range
        self.parentRange = parentRange
        self.parentKind = parentKind
        self.preserveLineHeight = preserveLineHeight
    }
}

/// Cached data from a full style pass, used for lightweight cursor-only updates.
struct StylePassCache {
    let markers: [SyntaxMarker]
    let imageSpans: [(range: NSRange, source: String?, altText: String)]
    let fontScale: CGFloat
    let lineSpacing: CGFloat
}

/// Calculates syntax marker ranges for different markdown elements.
enum SyntaxMarkerCalculator {
    /// Returns syntax marker ranges for a given style span.
    /// - Parameters:
    ///   - span: The style span with source range
    ///   - text: The source text
    /// - Returns: Array of syntax markers (prefix and suffix ranges)
    static func markers(for span: StyleSpan, in text: String) -> [SyntaxMarker] {
        guard let nsRange = convertRange(span.sourceRange, in: text) else { return [] }
        let kind = span.kind

        switch kind {
        case .heading(let level):
            // # to ###### plus space = level + 1 characters prefix
            let prefixLen = min(level + 1, nsRange.length)
            let prefixRange = NSRange(location: nsRange.location, length: prefixLen)
            return [SyntaxMarker(range: prefixRange, parentRange: nsRange, parentKind: kind)]

        case .bold:
            // ** or __ prefix and suffix (2 chars each)
            guard nsRange.length >= 4 else { return [] }
            let prefixRange = NSRange(location: nsRange.location, length: 2)
            let suffixRange = NSRange(location: NSMaxRange(nsRange) - 2, length: 2)
            return [
                SyntaxMarker(range: prefixRange, parentRange: nsRange, parentKind: kind),
                SyntaxMarker(range: suffixRange, parentRange: nsRange, parentKind: kind)
            ]

        case .italic:
            // * or _ prefix and suffix (1 char each)
            guard nsRange.length >= 2 else { return [] }
            let prefixRange = NSRange(location: nsRange.location, length: 1)
            let suffixRange = NSRange(location: NSMaxRange(nsRange) - 1, length: 1)
            return [
                SyntaxMarker(range: prefixRange, parentRange: nsRange, parentKind: kind),
                SyntaxMarker(range: suffixRange, parentRange: nsRange, parentKind: kind)
            ]

        case .inlineCode:
            // ` prefix and suffix (1 char each, or `` for escaped)
            guard nsRange.length >= 2 else { return [] }
            // Check if double backticks
            let nsString = text as NSString
            let firstChar = nsString.substring(with: NSRange(location: nsRange.location, length: 1))
            let secondChar = nsRange.length > 1 ? nsString.substring(with: NSRange(location: nsRange.location + 1, length: 1)) : ""
            let backtickCount = (firstChar == "`" && secondChar == "`") ? 2 : 1

            guard nsRange.length >= backtickCount * 2 else { return [] }
            let prefixRange = NSRange(location: nsRange.location, length: backtickCount)
            let suffixRange = NSRange(location: NSMaxRange(nsRange) - backtickCount, length: backtickCount)
            return [
                SyntaxMarker(range: prefixRange, parentRange: nsRange, parentKind: kind),
                SyntaxMarker(range: suffixRange, parentRange: nsRange, parentKind: kind)
            ]

        case .link:
            // [text](url) - hide [ and ](url)
            guard nsRange.length >= 4 else { return [] }
            let nsString = text as NSString
            let content = nsString.substring(with: nsRange)

            // Find ]( position
            guard let closeBracketParenRange = content.range(of: "](") else { return [] }
            let closeBracketOffset = content.distance(from: content.startIndex, to: closeBracketParenRange.lowerBound)

            // [ at start
            let openBracketRange = NSRange(location: nsRange.location, length: 1)
            // ](...) from close bracket to end
            let urlPartRange = NSRange(
                location: nsRange.location + closeBracketOffset,
                length: nsRange.length - closeBracketOffset
            )

            return [
                SyntaxMarker(range: openBracketRange, parentRange: nsRange, parentKind: kind),
                SyntaxMarker(range: urlPartRange, parentRange: nsRange, parentKind: kind)
            ]

        case .blockquote:
            // > at start of each line - hide the > markers
            var markers: [SyntaxMarker] = []
            let nsString = text as NSString
            let content = nsString.substring(with: nsRange)
            let lines = content.components(separatedBy: .newlines)

            var offset = nsRange.location
            for line in lines {
                // Count leading > and space characters (for nested blockquotes)
                var markerLen = 0
                for char in line {
                    if char == ">" || char == " " {
                        markerLen += 1
                    } else {
                        break
                    }
                }
                if markerLen > 0 {
                    let markerRange = NSRange(location: offset, length: min(markerLen, line.utf16.count))
                    // For empty blockquote lines, preserve line height so the line doesn't collapse
                    let isEmptyLine = markerLen >= line.utf16.count
                    markers.append(SyntaxMarker(range: markerRange, parentRange: nsRange, parentKind: kind, preserveLineHeight: isEmptyLine))
                }
                offset += line.utf16.count + 1  // +1 for newline
            }
            return markers

        case .codeBlock:
            // ``` fences - find first and last lines
            let nsString = text as NSString
            let content = nsString.substring(with: nsRange)
            let lines = content.components(separatedBy: .newlines)

            guard lines.count >= 2 else { return [] }

            // Opening fence (first line)
            let openFenceLen = lines[0].utf16.count + 1 // +1 for newline
            let openRange = NSRange(location: nsRange.location, length: min(openFenceLen, nsRange.length))

            // Closing fence (last line)
            let lastLine = lines[lines.count - 1]
            if lastLine.hasPrefix("```") || lastLine.hasPrefix("~~~") {
                let closeLen = lastLine.utf16.count
                let closeStart = NSMaxRange(nsRange) - closeLen
                let closeRange = NSRange(location: max(nsRange.location, closeStart), length: closeLen)
                return [
                    SyntaxMarker(range: openRange, parentRange: nsRange, parentKind: kind),
                    SyntaxMarker(range: closeRange, parentRange: nsRange, parentKind: kind)
                ]
            }

            return [SyntaxMarker(range: openRange, parentRange: nsRange, parentKind: kind)]

        case .table, .tableHeader, .tableCell:
            // Tables: hide | characters - complex, skip for now
            return []

        case .frontmatter:
            // Frontmatter hiding handled separately
            return []

        case .image:
            // Hide entire markdown syntax ![alt](url) when cursor outside
            return [SyntaxMarker(range: nsRange, parentRange: nsRange, parentKind: kind)]
        }
    }
}

// MARK: - Range Conversion

/// Converts a swift-markdown SourceRange to NSRange for use with NSTextStorage.
///
/// swift-markdown's SourceLocation uses 1-indexed line and column (UTF-8 column offset).
/// This function converts line/column positions to absolute String indices, then to NSRange.
///
/// Returns nil if conversion fails (e.g., invalid line/column).
func convertRange(_ sourceRange: SourceRange, in text: String) -> NSRange? {
    guard let startIndex = sourceLocationToIndex(sourceRange.lowerBound, in: text),
          let endIndex = sourceLocationToIndex(sourceRange.upperBound, in: text),
          startIndex <= endIndex else {
        return nil
    }
    return NSRange(startIndex..<endIndex, in: text)
}

/// Converts a SourceLocation (1-indexed line, 1-indexed UTF-8 column) to a String.Index.
private func sourceLocationToIndex(_ location: SourceLocation, in text: String) -> String.Index? {
    let line = location.line
    let column = location.column
    
    guard line >= 1, column >= 1 else { return nil }
    
    var currentLine = 1
    var lineStartIndex = text.startIndex
    
    // Find the start of the target line
    while currentLine < line {
        guard let newlineIndex = text[lineStartIndex...].firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            // Ran out of lines before reaching target
            return nil
        }
        lineStartIndex = text.index(after: newlineIndex)
        // Handle \r\n as single newline
        if text[newlineIndex] == "\r",
           lineStartIndex < text.endIndex,
           text[lineStartIndex] == "\n" {
            lineStartIndex = text.index(after: lineStartIndex)
        }
        currentLine += 1
    }
    
    // Now lineStartIndex is at the beginning of the target line
    // Column is 1-indexed UTF-8 offset from line start
    let lineSlice = text[lineStartIndex...]
    let utf8View = lineSlice.utf8
    let utf8Offset = column - 1  // Convert to 0-indexed
    
    guard utf8Offset >= 0, utf8Offset <= utf8View.count else { return nil }
    
    let targetUTF8Index = utf8View.index(utf8View.startIndex, offsetBy: utf8Offset)
    return targetUTF8Index.samePosition(in: text)
}

// MARK: - StyleCollector (MarkupVisitor)

struct StyleCollector: MarkupWalker {
    private(set) var spans: [StyleSpan] = []
    private var blockquoteNestingLevel = 0

    mutating func visitHeading(_ heading: Heading) {
        if let range = heading.range {
            spans.append(StyleSpan(sourceRange: range, kind: .heading(level: heading.level)))
        }
        descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = strong.range {
            spans.append(StyleSpan(sourceRange: range, kind: .bold))
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = emphasis.range {
            spans.append(StyleSpan(sourceRange: range, kind: .italic))
        }
        descendInto(emphasis)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let range = inlineCode.range {
            spans.append(StyleSpan(sourceRange: range, kind: .inlineCode))
        }
    }

    mutating func visitLink(_ link: Link) {
        if let range = link.range {
            spans.append(StyleSpan(sourceRange: range, kind: .link))
        }
        descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        blockquoteNestingLevel += 1
        if let range = blockQuote.range {
            spans.append(StyleSpan(sourceRange: range, kind: .blockquote(nestingLevel: blockquoteNestingLevel)))
        }
        descendInto(blockQuote)
        blockquoteNestingLevel -= 1
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = codeBlock.range {
            spans.append(StyleSpan(sourceRange: range, kind: .codeBlock))
        }
    }

    mutating func visitTable(_ table: Table) {
        if let range = table.range {
            spans.append(StyleSpan(sourceRange: range, kind: .table))
        }
        descendInto(table)
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        if let range = tableHead.range {
            spans.append(StyleSpan(sourceRange: range, kind: .tableHeader))
        }
        descendInto(tableHead)
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        if let range = tableCell.range {
            spans.append(StyleSpan(sourceRange: range, kind: .tableCell))
        }
        descendInto(tableCell)
    }

    mutating func visitImage(_ image: Markdown.Image) {
        if let range = image.range {
            let source = image.source
            let altText = image.plainText
            spans.append(StyleSpan(sourceRange: range, kind: .image(source: source, altText: altText)))
        }
    }
}

// MARK: - Image Rendering

/// Custom attribute keys for styling
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

// MARK: - Image Context

/// Context for resolving image paths relative to Hugo's site structure.
struct ImageContext {
    let postURL: URL           // URL of the current .md file
    let siteURL: URL           // URL of the Hugo site root
    let remoteImagesEnabled: Bool

    init(postURL: URL, siteURL: URL, remoteImagesEnabled: Bool = false) {
        self.postURL = postURL
        self.siteURL = siteURL
        self.remoteImagesEnabled = remoteImagesEnabled
    }
    
    /// Resolves an image path according to Hugo conventions:
    /// - `/some-path/my-image.png` → static/some-path/my-image.png
    /// - `assets/my-image.png` → assets/my-image.png
    /// - `my-image.png` → same directory as the post
    func resolveImagePath(_ source: String) -> URL? {
        guard !source.isEmpty else { return nil }

        // Handle remote URLs
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return remoteImagesEnabled ? URL(string: source) : nil
        }
        
        if source.hasPrefix("/") {
            // Absolute path from site root -> static/
            let relativePath = String(source.dropFirst())
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("static").appendingPathComponent(relativePath)
            )
        }

        if source.hasPrefix("assets/") {
            let relativePath = String(source.dropFirst("assets/".count))
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("assets").appendingPathComponent(relativePath)
            )
        }

        if source.hasPrefix("static/") {
            let relativePath = String(source.dropFirst("static/".count))
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("static").appendingPathComponent(relativePath)
            )
        }

        // Relative path from post's directory
        let postDirectory = postURL.deletingLastPathComponent()
        return sanitizedLocalURL(postDirectory.appendingPathComponent(source))
    }

    private func sanitizedLocalURL(_ url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let sitePath = siteURL.standardizedFileURL.path
        let postPath = postURL.deletingLastPathComponent().standardizedFileURL.path
        let candidatePath = standardized.path

        guard candidatePath.hasPrefix(sitePath) || candidatePath.hasPrefix(postPath) else {
            return nil
        }

        return standardized
    }
}

// MARK: - Image Cache

/// Simple in-memory cache for loaded images.
final class ImageCache {
    static let shared = ImageCache()

    private struct Entry {
        let image: NSImage
        let cost: Int
    }

    private var cache: [URL: Entry] = [:]
    private var order: [URL] = []
    private var totalCost: Int = 0
    private let countLimit: Int
    private let totalCostLimit: Int
    private let queue = DispatchQueue(label: "com.hugora.imagecache", attributes: .concurrent)

    init(countLimit: Int = 128, totalCostLimit: Int = 128 * 1024 * 1024) {
        self.countLimit = max(countLimit, 1)
        self.totalCostLimit = max(totalCostLimit, 1)
    }

    func image(for url: URL) -> NSImage? {
        queue.sync {
            guard let entry = cache[url] else { return nil }
            markAsRecentlyUsed(url)
            return entry.image
        }
    }

    func setImage(_ image: NSImage, for url: URL) {
        let cost = imageCost(image)
        queue.sync(flags: .barrier) {
            if let existing = cache[url] {
                totalCost -= existing.cost
                removeFromOrder(url)
            }

            cache[url] = Entry(image: image, cost: cost)
            order.append(url)
            totalCost += cost
            enforceLimits()
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            cache.removeAll()
            order.removeAll()
            totalCost = 0
        }
    }

    private func markAsRecentlyUsed(_ url: URL) {
        guard let index = order.firstIndex(of: url) else { return }
        order.remove(at: index)
        order.append(url)
    }

    private func removeFromOrder(_ url: URL) {
        if let index = order.firstIndex(of: url) {
            order.remove(at: index)
        }
    }

    private func enforceLimits() {
        while cache.count > countLimit || totalCost > totalCostLimit {
            guard let oldest = order.first,
                  let entry = cache[oldest] else {
                break
            }
            cache.removeValue(forKey: oldest)
            order.removeFirst()
            totalCost -= entry.cost
        }
    }

    private func imageCost(_ image: NSImage) -> Int {
        let reps = image.representations
        let maxPixels = reps.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
        let fallbackPixels = Int(image.size.width * image.size.height)
        let pixels = max(maxPixels, fallbackPixels)
        return max(pixels * 4, 1)
    }
}

// MARK: - MarkdownStyler

struct MarkdownStyler {
    let theme: Theme

    init(theme: Theme = .default) {
        self.theme = theme
    }

    /// Convenience wrapper matching EditorViewModel's expected API.
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
                fontScale: fontScale
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
                    let hiddenFont = NSFont.systemFont(ofSize: 0.01)
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
        fontScale: CGFloat
    ) {
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: textStorage.length))
        guard clampedRange.length > 0 else { return }
        
        let font = scaledFont(theme.frontmatterFont, scale: fontScale)
        textStorage.addAttribute(.font, value: font, range: clampedRange)
        textStorage.addAttribute(.foregroundColor, value: theme.frontmatterColor, range: clampedRange)
        textStorage.addAttribute(.backgroundColor, value: theme.frontmatterBackground, range: clampedRange)
        
        // Highlight YAML keys (word followed by colon at start of line)
        let nsString = textStorage.string as NSString
        let content = nsString.substring(with: clampedRange)
        let lines = content.components(separatedBy: .newlines)
        var offset = clampedRange.location
        
        for line in lines {
            if let colonIdx = line.firstIndex(of: ":"), colonIdx != line.startIndex {
                let keyLength = line.distance(from: line.startIndex, to: colonIdx)
                let keyRange = NSRange(location: offset, length: keyLength)
                textStorage.addAttribute(.foregroundColor, value: theme.frontmatterKeyColor, range: keyRange)
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
            
            if cursorInElement {
                // Show syntax: ensure normal visibility (already applied by base styling)
                // Nothing extra needed - syntax is visible by default
            } else {
                // Hide syntax: make it nearly invisible
                let clampedRange = NSIntersectionRange(marker.range, NSRange(location: 0, length: textStorage.length))
                guard clampedRange.length > 0 else { continue }
                
                if marker.preserveLineHeight {
                    // For empty blockquote lines: hide color only, keep font to preserve line height
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
                } else {
                    // Normal hiding: tiny font to collapse space while maintaining string integrity
                    let hiddenFont = NSFont.systemFont(ofSize: 0.01)
                    textStorage.addAttribute(.font, value: hiddenFont, range: clampedRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.clear, range: clampedRange)
                }
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
            let indent: CGFloat = CGFloat(nestingLevel) * 20  // 20pt per nesting level
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
                // Cursor is in image: show raw markdown, remove any attachment
                showImageMarkdown(
                    range: range,
                    source: imageSpan.source,
                    altText: imageSpan.altText,
                    textStorage: textStorage,
                    theme: theme,
                    fontScale: fontScale,
                    lineSpacing: lineSpacing
                )
                continue
            }

            // Cursor outside: load and display image
            guard let source = imageSpan.source,
                  let imageURL = imageContext.resolveImagePath(source) else {
                showImageMarkdown(
                    range: range,
                    source: imageSpan.source,
                    altText: imageSpan.altText,
                    textStorage: textStorage,
                    theme: theme,
                    fontScale: fontScale,
                    lineSpacing: lineSpacing
                )
                continue
            }

            guard imageURL.isFileURL else {
                showImageMarkdown(
                    range: range,
                    source: imageSpan.source,
                    altText: imageSpan.altText,
                    textStorage: textStorage,
                    theme: theme,
                    fontScale: fontScale,
                    lineSpacing: lineSpacing
                )
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
                showImageMarkdown(
                    range: range,
                    source: imageSpan.source,
                    altText: imageSpan.altText,
                    textStorage: textStorage,
                    theme: theme,
                    fontScale: fontScale,
                    lineSpacing: lineSpacing
                )
                continue
            }

            // Store image info as custom attribute for later rendering
            // NSTextAttachment only works with the U+FFFC character, not arbitrary text
            // We'll use custom drawing in EditorTextView instead
            let maxWidth: CGFloat = 600
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
            paragraphStyle.paragraphSpacing = targetHeight + 12  // image height + padding
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
    
    /// Creates an NSTextAttachment with the image scaled to fit the text container.
    private func createImageAttachment(image: NSImage, altText: String, maxWidth: CGFloat = 600) -> NSTextAttachment {
        // Scale image to fit within maxWidth while preserving aspect ratio
        let originalSize = image.size
        var targetSize = originalSize
        
        if originalSize.width > maxWidth {
            let scale = maxWidth / originalSize.width
            targetSize = NSSize(width: maxWidth, height: originalSize.height * scale)
        }
        
        // Use custom attachment cell for better rendering control
        let cell = NSTextAttachmentCell(imageCell: image)
        cell.image = image
        
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        
        // Set bounds to control display size (the cell will scale the image)
        attachment.bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: targetSize)
        
        #if DEBUG
        print("[ImageDebug] Created attachment with bounds: \(attachment.bounds), cell: \(String(describing: attachment.attachmentCell))")
        #endif
        
        return attachment
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
