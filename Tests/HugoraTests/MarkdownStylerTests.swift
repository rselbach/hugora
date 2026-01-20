import Testing
import AppKit
import Markdown
@testable import Hugora

// MARK: - Range Conversion Tests

@Suite("Range Conversion")
struct RangeConversionTests {
    @Test("Single-line text converts correctly")
    func testSingleLineConversion() {
        let text = "Hello, world!"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 1, source: nil),
                upper: SourceLocation(line: 1, column: 6, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == NSRange(location: 0, length: 5))
    }

    @Test("Multi-line text converts correctly")
    func testMultiLineConversion() {
        let text = "Line one\nLine two\nLine three"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 2, column: 1, source: nil),
                upper: SourceLocation(line: 2, column: 9, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == NSRange(location: 9, length: 8))
    }

    @Test("Multi-line span converts correctly")
    func testMultiLineSpan() {
        let text = "Line one\nLine two\nLine three"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 6, source: nil),
                upper: SourceLocation(line: 2, column: 5, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == NSRange(location: 5, length: 8))
    }

    @Test("Unicode emoji converts correctly")
    func testUnicodeEmoji() {
        let text = "Hi 👋 there"
        // 👋 is 4 bytes in UTF-8, so "there" starts at column 9 (H=1, i=2, space=3, emoji=4-7, space=8, t=9)
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 9, source: nil),
                upper: SourceLocation(line: 1, column: 14, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        let extracted = (text as NSString).substring(with: result!)
        #expect(extracted == "there")
    }

    @Test("Multi-byte characters convert correctly")
    func testMultiByteCharacters() {
        let text = "你好世界"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 1, source: nil),
                upper: SourceLocation(line: 1, column: 7, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        let extracted = (text as NSString).substring(with: result!)
        #expect(extracted == "你好")
    }

    @Test("Invalid line returns nil")
    func testInvalidLine() {
        let text = "Single line"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 5, column: 1, source: nil),
                upper: SourceLocation(line: 5, column: 5, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == nil)
    }

    @Test("Zero line returns nil")
    func testZeroLine() {
        let text = "Hello"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 0, column: 1, source: nil),
                upper: SourceLocation(line: 1, column: 3, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == nil)
    }

    @Test("Zero column returns nil")
    func testZeroColumn() {
        let text = "Hello"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 0, source: nil),
                upper: SourceLocation(line: 1, column: 3, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == nil)
    }

    @Test("Column beyond line length returns nil")
    func testColumnBeyondLineLength() {
        let text = "Hi"
        let sourceRange = SourceRange(
            uncheckedBounds: (
                lower: SourceLocation(line: 1, column: 1, source: nil),
                upper: SourceLocation(line: 1, column: 100, source: nil)
            )
        )
        let result = convertRange(sourceRange, in: text)
        #expect(result == nil)
    }
}

// MARK: - StyleCollector Tests

@Suite("StyleCollector")
struct StyleCollectorTests {
    @Test("Collects heading with correct level")
    func testHeadingCollection() {
        let markdown = "# Heading 1\n## Heading 2"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let headings = collector.spans.filter {
            if case .heading = $0.kind { return true }
            return false
        }
        #expect(headings.count == 2)

        if case .heading(let level) = headings[0].kind {
            #expect(level == 1)
        }
        if case .heading(let level) = headings[1].kind {
            #expect(level == 2)
        }
    }

    @Test("Collects bold spans")
    func testBoldCollection() {
        let markdown = "Some **bold** text"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let bolds = collector.spans.filter {
            if case .bold = $0.kind { return true }
            return false
        }
        #expect(bolds.count == 1)
    }

    @Test("Collects italic spans")
    func testItalicCollection() {
        let markdown = "Some *italic* text"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let italics = collector.spans.filter {
            if case .italic = $0.kind { return true }
            return false
        }
        #expect(italics.count == 1)
    }

    @Test("Collects inline code spans")
    func testInlineCodeCollection() {
        let markdown = "Use `code` here"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let codes = collector.spans.filter {
            if case .inlineCode = $0.kind { return true }
            return false
        }
        #expect(codes.count == 1)
    }

    @Test("Collects link spans")
    func testLinkCollection() {
        let markdown = "Click [here](https://example.com)"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let links = collector.spans.filter {
            if case .link = $0.kind { return true }
            return false
        }
        #expect(links.count == 1)
    }

    @Test("Collects blockquote spans")
    func testBlockquoteCollection() {
        let markdown = "> This is a quote"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let quotes = collector.spans.filter {
            if case .blockquote = $0.kind { return true }
            return false
        }
        #expect(quotes.count == 1)
    }

    @Test("Collects code block spans")
    func testCodeBlockCollection() {
        let markdown = "```\nlet x = 1\n```"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let codeBlocks = collector.spans.filter {
            if case .codeBlock = $0.kind { return true }
            return false
        }
        #expect(codeBlocks.count == 1)
    }

    @Test("Collects table spans")
    func testTableCollection() {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let tables = collector.spans.filter {
            if case .table = $0.kind { return true }
            return false
        }
        let headers = collector.spans.filter {
            if case .tableHeader = $0.kind { return true }
            return false
        }
        #expect(tables.count == 1)
        #expect(headers.count == 1)
    }

    @Test("Nested markup produces multiple spans")
    func testNestedMarkup() {
        let markdown = "# **Bold heading**"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let headings = collector.spans.filter {
            if case .heading = $0.kind { return true }
            return false
        }
        let bolds = collector.spans.filter {
            if case .bold = $0.kind { return true }
            return false
        }

        #expect(headings.count == 1)
        #expect(bolds.count == 1)
    }

    @Test("Bold inside italic produces both spans")
    func testBoldInsideItalic() {
        let markdown = "*italic **bold** italic*"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)

        let italics = collector.spans.filter {
            if case .italic = $0.kind { return true }
            return false
        }
        let bolds = collector.spans.filter {
            if case .bold = $0.kind { return true }
            return false
        }

        #expect(italics.count == 1)
        #expect(bolds.count == 1)
    }
}

// MARK: - Style Application Integration Tests

@Suite("Style Application")
struct StyleApplicationTests {
    let theme = Theme.default
    let styler = MarkdownStyler(theme: .default)

    @Test("Headings get larger fonts")
    func testHeadingFontSize() {
        let markdown = "# Big Heading"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)

        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange)

        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: 2, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > theme.baseFont.pointSize)
    }

    @Test("Bold text has bold trait")
    func testBoldTrait() {
        let markdown = "Some **bold** word"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        
        // Pass cursor position inside the bold element so syntax isn't hidden
        let cursorInBold = 7
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: cursorInBold)

        // Check content position (after **), not syntax marker
        let boldContentStart = 7 // "b" in "bold"
        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: boldContentStart, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)

        let traits = NSFontManager.shared.traits(of: font!)
        #expect(traits.contains(.boldFontMask))
    }

    @Test("Italic text has italic trait")
    func testItalicTrait() {
        let markdown = "Some *italic* word"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        
        // Pass cursor position inside the italic element so syntax isn't hidden
        let cursorInItalic = 6
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: cursorInItalic)

        // Check content position (after *), not syntax marker
        let italicContentStart = 6 // "i" in "italic"
        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: italicContentStart, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)

        let traits = NSFontManager.shared.traits(of: font!)
        #expect(traits.contains(.italicFontMask))
    }

    @Test("Inline code has monospace font")
    func testInlineCodeMonospace() {
        let markdown = "Use `code` here"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        
        // Pass cursor position inside the code element so syntax isn't hidden
        let cursorInCode = 5
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: cursorInCode)

        // Check content position (after `), not syntax marker
        let codeContentStart = 5 // "c" in "code"
        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: codeContentStart, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)
        #expect(font!.isFixedPitch)
    }

    @Test("Styles don't corrupt string content")
    func testContentIntegrity() {
        let markdown = "# Heading\n\n**bold** and *italic* with `code`"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)

        let originalContent = textStorage.string

        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange)

        #expect(textStorage.string == originalContent)
        #expect(textStorage.length == originalContent.count)
    }

    @Test("Links get link color")
    func testLinkColor() {
        let markdown = "Click [here](https://example.com)"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        
        // Pass cursor position inside the link element so syntax isn't hidden
        let cursorInLink = 7
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: cursorInLink)

        // Check content position (after [), not syntax marker
        let linkContentStart = 7 // "h" in "here"
        var effectiveRange = NSRange()
        let color = textStorage.attribute(.foregroundColor, at: linkContentStart, effectiveRange: &effectiveRange) as? NSColor
        #expect(color == theme.linkColor)
    }

    @Test("Empty visible range doesn't crash")
    func testEmptyVisibleRange() {
        let markdown = "# Test"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: 0)

        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange)
        #expect(textStorage.string == markdown)
    }
}

// MARK: - Theme Tests

@Suite("Themes")
struct ThemeTests {
    @Test("Theme.named returns correct theme for each name")
    func testThemeNamed() {
        let names = ["Default", "GitHub", "Dracula", "Solarized Light", "Solarized Dark"]
        for name in names {
            let theme = Theme.named(name)
            #expect(theme.baseFont.pointSize > 0)
            #expect(theme.headings.count == 6)
        }
    }

    @Test("Dracula theme has purple headings")
    func testDraculaHeadings() {
        let theme = Theme.dracula
        let headingColor = theme.headings[0].color
        #expect(headingColor != NSColor.textColor)
    }

    @Test("Solarized themes have orange headings")
    func testSolarizedHeadings() {
        let light = Theme.solarizedLight
        let dark = Theme.solarizedDark
        #expect(light.headings[0].color == dark.headings[0].color)
    }

    @Test("GitHub light and dark have different text colors")
    func testGitHubAppearance() {
        let light = Theme.githubLight
        let dark = Theme.githubDark
        #expect(light.baseColor != dark.baseColor)
    }

    @Test("Theme applies custom colors to styled text")
    func testThemeAppliesColors() {
        let markdown = "[link](https://example.com)"
        let dracula = Theme.dracula
        let styler = MarkdownStyler(theme: dracula)
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        
        // Place cursor inside link so content is visible
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 2)

        var effectiveRange = NSRange()
        // Check position 1 which is "l" in "link" (after [)
        let color = textStorage.attribute(.foregroundColor, at: 1, effectiveRange: &effectiveRange) as? NSColor
        #expect(color == dracula.linkColor)
    }
}

// MARK: - Syntax Hiding Tests

@Suite("Syntax Hiding")
struct SyntaxHidingTests {
    let theme = Theme.default
    lazy var styler = MarkdownStyler(theme: theme)
    
    @Test("Bold syntax hidden when cursor outside")
    func testBoldSyntaxHidden() {
        let markdown = "Some **bold** text"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor at position 0 (outside bold element)
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 0)
        
        // Check ** at position 5-6 is hidden (tiny font)
        let font = textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize < 1.0) // Hidden = tiny font
    }
    
    @Test("Bold syntax visible when cursor inside")
    func testBoldSyntaxVisible() {
        let markdown = "Some **bold** text"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor at position 8 (inside "bold")
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 8)
        
        // Check ** at position 5 is visible (normal font)
        let font = textStorage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        let storedFontSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double
        let expectedBase = CGFloat(storedFontSize ?? Double(theme.baseFont.pointSize))
        #expect(font!.pointSize >= expectedBase)
    }
    
    @Test("Heading hash hidden when cursor outside")
    func testHeadingHashHidden() {
        let markdown = "# Heading\n\nParagraph"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor in paragraph (position 12)
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 15)
        
        // Check # at position 0 is hidden
        let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize < 1.0)
    }
    
    @Test("Heading hash visible when cursor on heading line")
    func testHeadingHashVisible() {
        let markdown = "# Heading\n\nParagraph"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor on heading (position 5)
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 5)
        
        // Check # at position 0 is visible
        let font = textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize > 1.0)
    }
    
    @Test("Link URL hidden when cursor outside")
    func testLinkUrlHidden() {
        let markdown = "Click [here](https://example.com) now"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor at end (outside link)
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 35)
        
        // Check [ at position 6 is hidden
        let bracketFont = textStorage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(bracketFont != nil)
        #expect(bracketFont!.pointSize < 1.0)
        
        // Check URL part is hidden (position 12 is inside ](url))
        let urlFont = textStorage.attribute(.font, at: 12, effectiveRange: nil) as? NSFont
        #expect(urlFont != nil)
        #expect(urlFont!.pointSize < 1.0)
    }
    
    @Test("String content unchanged after syntax hiding")
    func testContentUnchanged() {
        let markdown = "# Title\n\n**bold** and *italic* with `code`"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 0)
        
        #expect(textStorage.string == markdown)
    }
}

// MARK: - Image Tests

@Suite("Image Handling")
struct ImageHandlingTests {
    @Test("Collects image spans with source and alt text")
    func testImageCollection() {
        let markdown = "![Alt text](image.png)"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)
        
        let images = collector.spans.filter {
            if case .image = $0.kind { return true }
            return false
        }
        #expect(images.count == 1)
        
        if case .image(let source, let altText) = images[0].kind {
            #expect(source == "image.png")
            #expect(altText == "Alt text")
        } else {
            Issue.record("Expected image span")
        }
    }
    
    @Test("Collects image with empty alt text")
    func testImageEmptyAlt() {
        let markdown = "![](photo.jpg)"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)
        
        let images = collector.spans.filter {
            if case .image = $0.kind { return true }
            return false
        }
        #expect(images.count == 1)
        
        if case .image(let source, let altText) = images[0].kind {
            #expect(source == "photo.jpg")
            #expect(altText == "")
        }
    }
    
    @Test("Collects multiple images")
    func testMultipleImages() {
        let markdown = "![One](a.png) and ![Two](b.png)"
        let document = Document(parsing: markdown)
        var collector = StyleCollector()
        collector.visit(document)
        
        let images = collector.spans.filter {
            if case .image = $0.kind { return true }
            return false
        }
        #expect(images.count == 2)
    }
    
    @Test("Image context resolves relative path")
    func testRelativePathResolution() throws {
        let postURL = URL(fileURLWithPath: "/tmp/greendale/site/content/blog/my-post/index.md")
        let blogDir = URL(fileURLWithPath: "/tmp/greendale/site/content/blog")
        let context = ImageContext(postURL: postURL, blogDirectoryURL: blogDir)
        
        let resolved = context.resolveImagePath("photo.png")
        #expect(resolved?.path == "/tmp/greendale/site/content/blog/my-post/photo.png")
    }
    
    @Test("Image context resolves absolute path from blog root")
    func testAbsolutePathResolution() throws {
        let postURL = URL(fileURLWithPath: "/tmp/greendale/site/content/blog/my-post/index.md")
        let blogDir = URL(fileURLWithPath: "/tmp/greendale/site/content/blog")
        let context = ImageContext(postURL: postURL, blogDirectoryURL: blogDir)
        
        let resolved = context.resolveImagePath("/other-post/image.png")
        #expect(resolved?.path == "/tmp/greendale/site/content/blog/other-post/image.png")
    }
    
    @Test("Image context handles remote URLs")
    func testRemoteURL() {
        let postURL = URL(fileURLWithPath: "/tmp/greendale/site/content/blog/post.md")
        let blogDir = URL(fileURLWithPath: "/tmp/greendale/site/content/blog")
        let context = ImageContext(postURL: postURL, blogDirectoryURL: blogDir)
        
        let resolved = context.resolveImagePath("https://example.com/image.png")
        #expect(resolved?.absoluteString == "https://example.com/image.png")
    }
    
    @Test("Image context returns nil for empty source")
    func testEmptySource() {
        let postURL = URL(fileURLWithPath: "/tmp/greendale/site/content/blog/post.md")
        let blogDir = URL(fileURLWithPath: "/tmp/greendale/site/content/blog")
        let context = ImageContext(postURL: postURL, blogDirectoryURL: blogDir)
        
        let resolved = context.resolveImagePath("")
        #expect(resolved == nil)
    }
    
    @Test("Image syntax hidden when cursor outside")
    func testImageSyntaxHidden() {
        let markdown = "Text\n\n![Alt](img.png)\n\nMore"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor at beginning, outside image
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 0)
        
        // Image syntax should be hidden (tiny font)
        let imageStart = 6 // "![Alt](img.png)" starts after "Text\n\n"
        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: imageStart, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize < 1.0)
    }
    
    @Test("Image syntax visible when cursor inside")
    func testImageSyntaxVisible() {
        let markdown = "![Alt](img.png)"
        let textStorage = NSTextStorage(string: markdown)
        let document = Document(parsing: markdown)
        let visibleRange = NSRange(location: 0, length: textStorage.length)
        let styler = MarkdownStyler(theme: Theme.default)
        
        // Cursor inside the image markdown
        styler.style(text: markdown, document: document, textStorage: textStorage, visibleRange: visibleRange, cursorPosition: 5)
        
        // Image syntax should be visible (normal font)
        var effectiveRange = NSRange()
        let font = textStorage.attribute(.font, at: 0, effectiveRange: &effectiveRange) as? NSFont
        #expect(font != nil)
        #expect(font!.pointSize >= 1.0)
    }
}
