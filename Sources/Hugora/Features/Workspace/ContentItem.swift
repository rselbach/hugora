import Foundation

func slugify(_ string: String) -> String {
    string
        .lowercased()
        .replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: "'", with: "")
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
}

func parseFrontmatterValue(key: String, from content: String) -> String? {
    let lines = content.components(separatedBy: .newlines)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }

    for line in lines.dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" || trimmed == "+++" { break }

        if trimmed.lowercased().hasPrefix("\(key):") {
            var value = String(trimmed.dropFirst(key.count + 1))
                .trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
    }
    return nil
}

enum ContentFormat: String, Codable, CaseIterable {
    case bundle  // content/section/slug/index.md
    case file    // content/section/slug.md

    var displayName: String {
        switch self {
        case .bundle: "Bundle (folder/index.md)"
        case .file: "File (slug.md)"
        }
    }
}

struct ContentItem: Identifiable, Equatable, Comparable {
    let id: URL
    let url: URL          // path to the .md file
    let slug: String
    let title: String
    let format: ContentFormat
    let date: Date?
    let section: String

    init(url: URL, format: ContentFormat, section: String) {
        self.id = url
        self.url = url
        self.format = format
        self.section = section

        switch format {
        case .bundle:
            self.slug = url.deletingLastPathComponent().lastPathComponent
        case .file:
            self.slug = url.deletingPathExtension().lastPathComponent
        }

        self.title = Self.extractTitle(from: url) ?? slug
        self.date = Self.extractDate(from: url)
    }

    static func < (lhs: ContentItem, rhs: ContentItem) -> Bool {
        switch (lhs.date, rhs.date) {
        case let (l?, r?):
            return l > r  // newer first
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case (nil, nil):
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func extractTitle(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseFrontmatterValue(key: "title", from: content)
    }

    private static func extractDate(from url: URL) -> Date? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let dateString = parseFrontmatterValue(key: "date", from: content) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: String(dateString.prefix(10))) {
            return date
        }

        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd"
        return fallback.date(from: String(dateString.prefix(10)))
    }

}
