import AppKit
import Foundation

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
