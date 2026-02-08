import Foundation
import Markdown

// MARK: - StyleKind

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

// MARK: - StyleSpan

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

// MARK: - StylePassCache

/// Cached data from a full style pass, used for lightweight cursor-only updates.
struct StylePassCache {
    let markers: [SyntaxMarker]
    let imageSpans: [(range: NSRange, source: String?, altText: String)]
    let fontScale: CGFloat
    let lineSpacing: CGFloat
}

// MARK: - SyntaxMarkerCalculator

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
