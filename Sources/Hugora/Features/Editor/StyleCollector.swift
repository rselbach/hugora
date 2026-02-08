import Markdown

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
