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
    guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) else { return nil }

    let delimiter: String
    switch firstLine {
    case "---":
        delimiter = "---"
    case "+++":
        delimiter = "+++"
    default:
        return nil
    }

    switch delimiter {
    case "---":
        return parseYAMLFrontmatterValue(key: key, lines: lines.dropFirst(), endDelimiter: delimiter)
    case "+++":
        return parseTOMLFrontmatterValue(key: key, lines: lines.dropFirst(), endDelimiter: delimiter)
    default:
        return nil
    }
}

private func parseYAMLFrontmatterValue(
    key: String,
    lines: ArraySlice<String>,
    endDelimiter: String
) -> String? {
    let lowerKey = key.lowercased()

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == endDelimiter { break }

        let lowerTrimmed = trimmed.lowercased()
        guard lowerTrimmed.hasPrefix("\(lowerKey):") else { continue }

        var value = String(trimmed.dropFirst(key.count + 1))
            .trimmingCharacters(in: .whitespaces)
        value = trimInlineValue(value)
        value = unquote(value)

        return value.isEmpty ? nil : value
    }

    return nil
}

private func parseTOMLFrontmatterValue(
    key: String,
    lines: ArraySlice<String>,
    endDelimiter: String
) -> String? {
    let lowerKey = key.lowercased()

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == endDelimiter { break }
        guard !trimmed.hasPrefix("#") else { continue }

        let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { continue }

        let keyPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard keyPart == lowerKey else { continue }

        var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        value = trimInlineValue(value)
        value = unquote(value)

        return value.isEmpty ? nil : value
    }

    return nil
}

private func stripInlineComment(from value: String) -> String {
    guard let hashIndex = value.firstIndex(of: "#") else { return value }
    let beforeHash = value[..<hashIndex].trimmingCharacters(in: .whitespaces)
    return String(beforeHash)
}

private func trimInlineValue(_ value: String) -> String {
    guard let firstChar = value.first else { return value }

    if firstChar == "\"" || firstChar == "'" {
        let afterFirst = value.index(after: value.startIndex)
        if let endQuote = value[afterFirst...].firstIndex(of: firstChar) {
            return String(value[afterFirst..<endQuote])
        }
    }

    return stripInlineComment(from: value)
}

private func unquote(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    if value.hasPrefix("\""), value.hasSuffix("\"") {
        return String(value.dropFirst().dropLast())
    }
    if value.hasPrefix("'"), value.hasSuffix("'") {
        return String(value.dropFirst().dropLast())
    }
    return value
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

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()

    private static let fallbackDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func extractDate(from url: URL) -> Date? {
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let dateString = parseFrontmatterValue(key: "date", from: content) else {
            return nil
        }

        let prefix = String(dateString.prefix(10))
        return isoDateFormatter.date(from: prefix)
            ?? fallbackDateFormatter.date(from: prefix)
    }

}
