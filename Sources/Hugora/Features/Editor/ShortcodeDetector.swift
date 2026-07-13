import Foundation

/// Finds Hugo shortcode tokens — `{{< ... >}}` and `{{% ... %}}` — so the
/// styler can treat them as verbatim text instead of markdown.
enum ShortcodeDetector {
    /// Returns the ranges of all complete shortcode tokens in `text`, in
    /// document order. Unterminated tokens are ignored. For paired
    /// shortcodes each tag is its own range; the body between them is
    /// regular markdown.
    static func shortcodeRanges(in text: String) -> [NSRange] {
        let nsString = text as NSString
        var ranges: [NSRange] = []
        var location = 0

        while location < nsString.length {
            let searchRange = NSRange(location: location, length: nsString.length - location)
            let angleOpen = nsString.range(of: "{{<", options: [], range: searchRange)
            let percentOpen = nsString.range(of: "{{%", options: [], range: searchRange)

            let open: NSRange
            let closeToken: String
            switch (angleOpen.location, percentOpen.location) {
            case (NSNotFound, NSNotFound):
                return ranges
            case (NSNotFound, _):
                open = percentOpen
                closeToken = "%}}"
            case (_, NSNotFound):
                open = angleOpen
                closeToken = ">}}"
            default:
                if angleOpen.location < percentOpen.location {
                    open = angleOpen
                    closeToken = ">}}"
                } else {
                    open = percentOpen
                    closeToken = "%}}"
                }
            }

            let afterOpen = NSMaxRange(open)
            let remainder = NSRange(location: afterOpen, length: nsString.length - afterOpen)
            let close = nsString.range(of: closeToken, options: [], range: remainder)
            guard close.location != NSNotFound else {
                // Unterminated: skip past the opener and keep scanning.
                location = afterOpen
                continue
            }

            ranges.append(NSRange(location: open.location, length: NSMaxRange(close) - open.location))
            location = NSMaxRange(close)
        }

        return ranges
    }
}
