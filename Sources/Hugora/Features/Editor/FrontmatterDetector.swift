import Foundation

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
