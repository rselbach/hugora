import AppKit

extension Theme {
    static func named(_ name: String, appearance: NSAppearance? = nil) -> Theme {
        let resolvedAppearance = appearance
            ?? NSApp?.effectiveAppearance
            ?? NSAppearance(named: .aqua)
            ?? .currentDrawing()
        let isDark = resolvedAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        switch name {
        case "GitHub":
            return isDark ? .githubDark : .githubLight
        case "Dracula":
            return .dracula
        case "Solarized Light":
            return .solarizedLight
        case "Solarized Dark":
            return .solarizedDark
        case "rselbach.com":
            return .rselbachCom
        default:
            return isDark ? .defaultDark : .defaultLight
        }
    }

    // MARK: - Default (System)

    static var defaultLight: Theme {
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

    static var defaultDark: Theme {
        defaultLight  // System colors adapt automatically
    }

    // MARK: - GitHub

    static var githubLight: Theme {
        let baseSize: CGFloat = 16
        let textColor = NSColor(hex: "#24292f")
        let headingColor = NSColor(hex: "#1f2328")
        let linkColor = NSColor(hex: "#0969da")
        let codeColor = NSColor(hex: "#1f2328")
        let codeBg = NSColor(hex: "#f6f8fa")
        let blockquoteColor = NSColor(hex: "#59636e")

        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: textColor,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.85, weight: .medium), color: headingColor),
            ],
            boldColor: textColor,
            italicColor: textColor,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            inlineCodeColor: codeColor,
            inlineCodeBackground: codeBg,
            linkColor: linkColor,
            blockquoteColor: blockquoteColor,
            blockquoteBorderColor: NSColor(hex: "#d1d9e0"),
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            codeBlockColor: codeColor,
            codeBlockBackground: codeBg,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            tableBackground: NSColor(hex: "#f6f8fa"),
            tableHeaderBackground: NSColor(hex: "#f0f3f6"),
            tableBorderColor: NSColor(hex: "#d1d9e0"),
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: NSColor(hex: "#59636e"),
            frontmatterBackground: NSColor(hex: "#f6f8fa"),
            frontmatterKeyColor: NSColor(hex: "#0550ae")
        )
    }

    static var githubDark: Theme {
        let baseSize: CGFloat = 16
        let textColor = NSColor(hex: "#e6edf3")
        let headingColor = NSColor(hex: "#ffffff")
        let linkColor = NSColor(hex: "#4493f8")
        let codeColor = NSColor(hex: "#e6edf3")
        let codeBg = NSColor(hex: "#161b22")
        let blockquoteColor = NSColor(hex: "#9198a1")

        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: textColor,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: headingColor),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.85, weight: .medium), color: headingColor),
            ],
            boldColor: textColor,
            italicColor: textColor,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            inlineCodeColor: codeColor,
            inlineCodeBackground: codeBg,
            linkColor: linkColor,
            blockquoteColor: blockquoteColor,
            blockquoteBorderColor: NSColor(hex: "#30363d"),
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            codeBlockColor: codeColor,
            codeBlockBackground: codeBg,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            tableBackground: NSColor(hex: "#161b22"),
            tableHeaderBackground: NSColor(hex: "#21262d"),
            tableBorderColor: NSColor(hex: "#30363d"),
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: NSColor(hex: "#9198a1"),
            frontmatterBackground: NSColor(hex: "#161b22"),
            frontmatterKeyColor: NSColor(hex: "#79c0ff")
        )
    }

    // MARK: - Dracula

    static var dracula: Theme {
        let baseSize: CGFloat = 16
        let foreground = NSColor(hex: "#f8f8f2")
        let comment = NSColor(hex: "#6272a4")
        let cyan = NSColor(hex: "#8be9fd")
        let pink = NSColor(hex: "#ff79c6")
        let purple = NSColor(hex: "#bd93f9")
        let bg = NSColor(hex: "#282a36")
        let selection = NSColor(hex: "#44475a")

        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: foreground,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: purple),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: purple),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: purple),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: purple),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: purple),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.9, weight: .medium), color: purple),
            ],
            boldColor: NSColor(hex: "#ffb86c"),  // orange
            italicColor: NSColor(hex: "#f1fa8c"),  // yellow
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            inlineCodeColor: pink,
            inlineCodeBackground: selection,
            linkColor: cyan,
            blockquoteColor: comment,
            blockquoteBorderColor: purple,
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            codeBlockColor: foreground,
            codeBlockBackground: bg,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            tableBackground: bg,
            tableHeaderBackground: selection,
            tableBorderColor: comment,
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: comment,
            frontmatterBackground: selection,
            frontmatterKeyColor: cyan
        )
    }

    // MARK: - rselbach.com

    static var rselbachCom: Theme {
        let baseSize: CGFloat = 16
        let text = NSColor(hex: "#e8e8e8")
        let amber = NSColor(hex: "#f59e0b")
        let muted = NSColor(hex: "#a0a0a0")
        let codeBg = NSColor(hex: "#242424")
        let codeBlockBg = NSColor(hex: "#1a1a1a")

        return Theme(
            baseFont: .monospacedSystemFont(ofSize: baseSize, weight: .regular),
            baseColor: text,
            headings: [
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize * 2.0, weight: .bold), color: amber),
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize * 1.5, weight: .bold), color: amber),
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize * 1.25, weight: .semibold), color: amber),
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize * 1.1, weight: .semibold), color: amber),
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize, weight: .medium), color: amber),
                HeadingStyle(font: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .medium), color: amber),
            ],
            boldColor: text,
            italicColor: text,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            inlineCodeColor: muted,
            inlineCodeBackground: codeBg,
            linkColor: amber,
            blockquoteColor: muted,
            blockquoteBorderColor: amber,
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            codeBlockColor: text,
            codeBlockBackground: codeBlockBg,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            tableBackground: codeBlockBg,
            tableHeaderBackground: codeBg,
            tableBorderColor: muted,
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: muted,
            frontmatterBackground: codeBg,
            frontmatterKeyColor: amber
        )
    }

    // MARK: - Solarized

    static var solarizedLight: Theme {
        let baseSize: CGFloat = 16
        let base00 = NSColor(hex: "#657b83")  // body text
        let base01 = NSColor(hex: "#586e75")  // emphasis
        let base1 = NSColor(hex: "#93a1a1")   // comments
        let base2 = NSColor(hex: "#eee8d5")   // background highlights
        let blue = NSColor(hex: "#268bd2")
        let cyan = NSColor(hex: "#2aa198")
        let orange = NSColor(hex: "#cb4b16")

        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: base00,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.9, weight: .medium), color: orange),
            ],
            boldColor: base01,
            italicColor: base01,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            inlineCodeColor: cyan,
            inlineCodeBackground: base2,
            linkColor: blue,
            blockquoteColor: base1,
            blockquoteBorderColor: orange,
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            codeBlockColor: base00,
            codeBlockBackground: base2,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            tableBackground: base2,
            tableHeaderBackground: base2.blended(withFraction: 0.3, of: .black) ?? base2,
            tableBorderColor: base1,
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: base1,
            frontmatterBackground: base2,
            frontmatterKeyColor: cyan
        )
    }

    static var solarizedDark: Theme {
        let baseSize: CGFloat = 16
        let base0 = NSColor(hex: "#839496")   // body text
        let base1 = NSColor(hex: "#93a1a1")   // emphasis
        let base01 = NSColor(hex: "#586e75")  // comments
        let base02 = NSColor(hex: "#073642")  // background highlights
        let blue = NSColor(hex: "#268bd2")
        let cyan = NSColor(hex: "#2aa198")
        let orange = NSColor(hex: "#cb4b16")

        return Theme(
            baseFont: .systemFont(ofSize: baseSize),
            baseColor: base0,
            headings: [
                HeadingStyle(font: .systemFont(ofSize: baseSize * 2.0, weight: .bold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.5, weight: .bold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.25, weight: .semibold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 1.1, weight: .semibold), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize, weight: .medium), color: orange),
                HeadingStyle(font: .systemFont(ofSize: baseSize * 0.9, weight: .medium), color: orange),
            ],
            boldColor: base1,
            italicColor: base1,
            inlineCodeFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            inlineCodeColor: cyan,
            inlineCodeBackground: base02,
            linkColor: blue,
            blockquoteColor: base01,
            blockquoteBorderColor: orange,
            codeBlockFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            codeBlockColor: base0,
            codeBlockBackground: base02,
            tableFont: .monospacedSystemFont(ofSize: baseSize * 0.9, weight: .regular),
            tableBackground: base02,
            tableHeaderBackground: base02.blended(withFraction: 0.15, of: .white) ?? base02,
            tableBorderColor: base01,
            frontmatterFont: .monospacedSystemFont(ofSize: baseSize * 0.85, weight: .regular),
            frontmatterColor: base01,
            frontmatterBackground: base02,
            frontmatterKeyColor: cyan
        )
    }
}

// MARK: - Hex Color Helper

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
