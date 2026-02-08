import Foundation
import Markdown

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
func sourceLocationToIndex(_ location: SourceLocation, in text: String) -> String.Index? {
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
