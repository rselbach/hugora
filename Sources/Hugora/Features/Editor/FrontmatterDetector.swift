import Foundation

// MARK: - Frontmatter Detection

enum FrontmatterFormat {
    case yaml
    case toml
    case json
}

struct FrontmatterRange {
    let format: FrontmatterFormat
    let range: NSRange
    let openingDelimiterRange: NSRange
    let closingDelimiterRange: NSRange
}

struct FrontmatterBlock {
    let format: FrontmatterFormat
    let range: NSRange
    let payload: String
}

func detectFrontmatter(in text: String) -> FrontmatterRange? {
    let nsString = text as NSString
    guard nsString.length > 0 else { return nil }

    let start = text.hasPrefix("\u{feff}") ? 1 : 0
    guard start < nsString.length else { return nil }

    if let range = detectDelimitedFrontmatter(in: nsString, start: start, delimiter: "---", format: .yaml) {
        return range
    }

    if let range = detectDelimitedFrontmatter(in: nsString, start: start, delimiter: "+++", format: .toml) {
        return range
    }

    if let range = detectJSONFrontmatter(in: nsString, start: start) {
        return range
    }

    return nil
}

func detectFrontmatterBlock(in text: String) -> FrontmatterBlock? {
    guard let detected = detectFrontmatter(in: text) else { return nil }
    let nsString = text as NSString

    switch detected.format {
    case .yaml, .toml:
        let payloadStart = NSMaxRange(detected.openingDelimiterRange)
        let payloadEnd = detected.closingDelimiterRange.location
        guard payloadEnd >= payloadStart else {
            return FrontmatterBlock(format: detected.format, range: detected.range, payload: "")
        }
        let payloadRange = NSRange(location: payloadStart, length: payloadEnd - payloadStart)
        return FrontmatterBlock(
            format: detected.format,
            range: detected.range,
            payload: nsString.substring(with: payloadRange)
        )
    case .json:
        return FrontmatterBlock(
            format: detected.format,
            range: detected.range,
            payload: nsString.substring(with: detected.range)
        )
    }
}

private func detectDelimitedFrontmatter(
    in nsString: NSString,
    start: Int,
    delimiter: String,
    format: FrontmatterFormat
) -> FrontmatterRange? {
    guard linePrefixMatches(nsString: nsString, start: start, delimiter: delimiter) else { return nil }
    guard let openingLineEnd = endOfLine(after: start, in: nsString) else { return nil }
    guard let closingLine = findClosingDelimiterLine(in: nsString, from: openingLineEnd, delimiter: delimiter) else {
        return nil
    }

    let fullRange = NSRange(location: start, length: closingLine.end - start)
    let openRange = NSRange(location: start, length: openingLineEnd - start)
    let closeRange = NSRange(location: closingLine.start, length: closingLine.end - closingLine.start)
    return FrontmatterRange(
        format: format,
        range: fullRange,
        openingDelimiterRange: openRange,
        closingDelimiterRange: closeRange
    )
}

private func detectJSONFrontmatter(in nsString: NSString, start: Int) -> FrontmatterRange? {
    guard start < nsString.length, nsString.character(at: start) == 0x7B else { // {
        return nil
    }

    var depth = 0
    var inString = false
    var escaped = false
    var index = start
    var closeBraceIndex: Int?

    while index < nsString.length {
        let char = nsString.character(at: index)

        if inString {
            if escaped {
                escaped = false
            } else if char == 0x5C { // \
                escaped = true
            } else if char == 0x22 { // "
                inString = false
            }
            index += 1
            continue
        }

        switch char {
        case 0x22: // "
            inString = true
        case 0x7B: // {
            depth += 1
        case 0x7D: // }
            depth -= 1
            if depth == 0 {
                closeBraceIndex = index
                index = nsString.length
                continue
            }
        default:
            break
        }
        index += 1
    }

    guard let closeBraceIndex else { return nil }
    let closeLineEnd = endOfLine(after: closeBraceIndex + 1, in: nsString) ?? (closeBraceIndex + 1)
    let fullRange = NSRange(location: start, length: closeLineEnd - start)
    let openRange = NSRange(location: start, length: 1)
    let closeRange = NSRange(location: closeBraceIndex, length: closeLineEnd - closeBraceIndex)
    return FrontmatterRange(
        format: .json,
        range: fullRange,
        openingDelimiterRange: openRange,
        closingDelimiterRange: closeRange
    )
}

private func linePrefixMatches(nsString: NSString, start: Int, delimiter: String) -> Bool {
    let delimiterLength = delimiter.utf16.count
    guard start + delimiterLength <= nsString.length else { return false }
    let prefixRange = NSRange(location: start, length: delimiterLength)
    guard nsString.substring(with: prefixRange) == delimiter else { return false }

    if start + delimiterLength == nsString.length {
        return true
    }

    let next = nsString.character(at: start + delimiterLength)
    return next == 0x0A || next == 0x0D
}

private func endOfLine(after index: Int, in nsString: NSString) -> Int? {
    guard index <= nsString.length else { return nil }
    var current = index
    while current < nsString.length {
        let char = nsString.character(at: current)
        if char == 0x0A {
            return current + 1
        }
        if char == 0x0D {
            if current + 1 < nsString.length, nsString.character(at: current + 1) == 0x0A {
                return current + 2
            }
            return current + 1
        }
        current += 1
    }
    return nsString.length
}

private func findClosingDelimiterLine(
    in nsString: NSString,
    from start: Int,
    delimiter: String
) -> (start: Int, end: Int)? {
    var lineStart = start
    while lineStart < nsString.length {
        let lineEnd = endOfLine(after: lineStart, in: nsString) ?? nsString.length
        let rawLineRange = NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
        let rawLine = nsString.substring(with: rawLineRange)
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == delimiter {
            return (lineStart, lineEnd)
        }

        lineStart = lineEnd
    }

    return nil
}
