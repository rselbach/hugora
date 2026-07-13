import Foundation

/// Computes the final URL a post will publish at, mirroring Hugo's
/// permalink rules closely enough for previewing and sharing: frontmatter
/// `url` wins, then a configured per-section permalink pattern, then the
/// default /section/slug-or-filename/ form.
enum PermalinkResolver {
    /// The absolute URL for a post, or nil when the site config has no
    /// usable baseURL.
    static func permalink(content: String, item: ContentItem, config: HugoConfig) -> String? {
        guard var base = config.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !base.isEmpty
        else {
            return nil
        }

        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base + relativePath(content: content, item: item, config: config)
    }

    /// The site-relative path (leading and trailing slash) for a post.
    static func relativePath(content: String, item: ContentItem, config: HugoConfig) -> String {
        if let explicit = FrontmatterParser.value(forKey: "url", in: content),
            !explicit.trimmingCharacters(in: .whitespaces).isEmpty
        {
            return normalized(explicit)
        }

        let slug = FrontmatterParser.value(forKey: "slug", in: content) ?? item.slug

        if let pattern = config.permalinks[item.section] {
            return normalized(expand(pattern: pattern, content: content, item: item, slug: slug))
        }

        if item.section == "(root)" {
            return normalized(slug)
        }
        return normalized("\(item.section)/\(slug)")
    }

    private static func expand(pattern: String, content: String, item: ContentItem, slug: String) -> String {
        let date = FrontmatterParser.date(forKey: "date", in: content) ?? item.date ?? Date()

        // Date-only frontmatter values are anchored at UTC midnight, so
        // extract components in UTC to match the written date.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)

        // Longest tokens first so :slugorfilename isn't clobbered by :slug.
        var expanded = pattern
        expanded = expanded.replacingOccurrences(of: ":slugorfilename", with: slug)
        expanded = expanded.replacingOccurrences(of: ":filename", with: item.slug)
        expanded = expanded.replacingOccurrences(of: ":section", with: item.section)
        expanded = expanded.replacingOccurrences(of: ":slug", with: slug)
        expanded = expanded.replacingOccurrences(of: ":title", with: Slug.from(item.title))
        expanded = expanded.replacingOccurrences(
            of: ":yearday", with: String(format: "%d", dayOfYear(date, calendar: calendar)))
        expanded = expanded.replacingOccurrences(of: ":year", with: year)
        expanded = expanded.replacingOccurrences(of: ":monthname", with: monthName(components.month ?? 1))
        expanded = expanded.replacingOccurrences(of: ":month", with: month)
        expanded = expanded.replacingOccurrences(of: ":day", with: day)
        return expanded
    }

    private static func dayOfYear(_ date: Date, calendar: Calendar) -> Int {
        calendar.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private static func monthName(_ month: Int) -> String {
        let names = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
        ]
        guard (1...12).contains(month) else { return "january" }
        return names[month - 1]
    }

    /// Ensures a leading and trailing slash, Hugo's pretty-URL form.
    private static func normalized(_ path: String) -> String {
        var result = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.hasPrefix("/") {
            result = "/" + result
        }
        if !result.hasSuffix("/") {
            result += "/"
        }
        return result
    }
}
