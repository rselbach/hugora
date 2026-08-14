import Foundation
import TOMLKit
import Yams
import os

enum Slug {
    static func from(_ string: String) -> String {
        string
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

enum ContentFile {
    static let supportedExtensions: Set<String> = ["md", "markdown"]

    static func isSupportedContentFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func basenameWithoutExtension(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func isLeafBundleIndex(_ url: URL) -> Bool {
        isBundleIndex(url, stem: "index")
    }

    static func isBranchBundleIndex(_ url: URL) -> Bool {
        isBundleIndex(url, stem: "_index")
    }

    /// Hugo accepts both index.md and language-qualified index.<lang>.md
    /// (multilingual sites) as bundle index files; same for _index.
    private static func isBundleIndex(_ url: URL, stem: String) -> Bool {
        let parts = basenameWithoutExtension(url).lowercased().components(separatedBy: ".")
        guard parts.count <= 2, parts.first == stem else { return false }
        return parts.count == 1 || !parts[1].isEmpty
    }
}

enum FrontmatterParser {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "FrontmatterParser"
    )

    static func value(forKey key: String, in content: String) -> String? {
        guard let value = rawValue(forKey: key, in: content) else { return nil }

        switch value {
        case let string as String:
            return string
        case let date as Date:
            return isoFormatter(fractionalSeconds: true).string(from: date)
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return nil
        }
    }

    /// Reads a list value (tags, categories, aliases). A scalar string is
    /// treated as a one-element list, matching Hugo's leniency.
    static func stringArray(forKey key: String, in content: String) -> [String] {
        guard let value = rawValue(forKey: key, in: content) else { return [] }

        switch value {
        case let list as [Any]:
            return list.compactMap { element in
                switch element {
                case let string as String: string
                case let number as NSNumber: number.stringValue
                default: nil
                }
            }
        case let string as String:
            return [string]
        default:
            return []
        }
    }

    static func bool(forKey key: String, in content: String) -> Bool? {
        guard let value = rawValue(forKey: key, in: content) else { return nil }

        switch value {
        case let bool as Bool:
            return bool
        case let string as String:
            switch string.lowercased() {
            case "true", "yes": return true
            case "false", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    static func date(forKey key: String, in content: String) -> Date? {
        guard let value = rawValue(forKey: key, in: content) else { return nil }

        switch value {
        case let date as Date:
            return date
        case let string as String:
            return parseDateString(string)
        case let number as NSNumber:
            let timestamp = number.doubleValue
            guard timestamp.isFinite else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        default:
            return nil
        }
    }

    private static func isoFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =
            fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    private static func fullDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }

    private static func customDateFormatters() -> [DateFormatter] {
        let formats = [
            "yyyy-MM-dd HH:mm:ssZZZZZ",
            "yyyy-MM-dd HH:mm:ss ZZZZZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            // Month-name styles Hugo also accepts (cast.StringToDate).
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "d MMM yyyy",
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }
    }

    private static func rawValue(forKey key: String, in content: String) -> Any? {
        guard let map = parseFrontmatter(in: content) else { return nil }
        let lowerKey = key.lowercased()
        return map.first { $0.key.lowercased() == lowerKey }?.value
    }

    private static func parseFrontmatter(in content: String) -> [String: Any]? {
        guard let block = detectFrontmatterBlock(in: content) else { return nil }

        switch block.format {
        case .yaml:
            return parseYAMLFrontmatter(block.payload)
        case .toml:
            return parseTOMLFrontmatter(block.payload)
        case .json:
            return parseJSONFrontmatter(block.payload)
        }
    }

    private static func parseYAMLFrontmatter(_ payload: String) -> [String: Any]? {
        do {
            return try Yams.load(yaml: payload) as? [String: Any]
        } catch {
            logger.error("Failed to parse YAML frontmatter: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseTOMLFrontmatter(_ payload: String) -> [String: Any]? {
        do {
            let table = try TOMLTable(string: payload)
            let jsonString = table.convert(to: .json)
            return parseJSONFrontmatter(jsonString)
        } catch {
            logger.error("Failed to parse TOML frontmatter: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseJSONFrontmatter(_ payload: String) -> [String: Any]? {
        guard let data = payload.data(using: .utf8) else { return nil }

        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            logger.error("Failed to parse JSON frontmatter: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseDateString(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let parsed = isoFormatter(fractionalSeconds: true).date(from: trimmed) {
            return parsed
        }

        if let parsed = isoFormatter(fractionalSeconds: false).date(from: trimmed) {
            return parsed
        }

        if let parsed = fullDateFormatter().date(from: trimmed) {
            return parsed
        }

        for formatter in customDateFormatters() {
            if let parsed = formatter.date(from: trimmed) {
                return parsed
            }
        }

        if let timestamp = Double(trimmed), timestamp.isFinite {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }
}

enum ContentFormat: String, Codable, CaseIterable {
    case bundle  // content/section/slug/index.*
    case file  // content/section/slug.*

    var displayName: String {
        switch self {
        case .bundle: "Bundle (folder/index.*)"
        case .file: "File (slug.*)"
        }
    }
}

struct ContentItem: Identifiable, Equatable, Comparable {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "ContentItem"
    )

    let id: URL
    let url: URL  // path to the .md file
    let slug: String
    let title: String
    let format: ContentFormat
    let date: Date?
    let section: String
    let isDraft: Bool
    let publishDate: Date?
    let tags: [String]
    let categories: [String]

    /// Pre-lowercased title for search filtering (avoids per-keystroke allocation).
    let searchTitle: String
    /// Pre-lowercased slug for search filtering.
    let searchSlug: String

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

        let content: String?
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            Self.logger.error("Failed to read content item \(url.lastPathComponent): \(error.localizedDescription)")
            content = nil
        }
        self.title = content.flatMap { FrontmatterParser.value(forKey: "title", in: $0) } ?? slug
        self.date = content.flatMap { Self.parseDate(from: $0) }
        self.isDraft = content.flatMap { FrontmatterParser.bool(forKey: "draft", in: $0) } ?? false
        self.publishDate = content.flatMap { FrontmatterParser.date(forKey: "publishDate", in: $0) }
        self.tags = content.map { FrontmatterParser.stringArray(forKey: "tags", in: $0) } ?? []
        self.categories = content.map { FrontmatterParser.stringArray(forKey: "categories", in: $0) } ?? []
        self.searchTitle = self.title.lowercased()
        self.searchSlug = self.slug.lowercased()
    }

    /// Create a ContentItem with metadata extracted from already-loaded content.
    /// Avoids a second file read when the caller has the content in hand.
    init(url: URL, format: ContentFormat, section: String, content: String) {
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

        self.title = FrontmatterParser.value(forKey: "title", in: content) ?? slug
        self.date = Self.parseDate(from: content)
        self.isDraft = FrontmatterParser.bool(forKey: "draft", in: content) ?? false
        self.publishDate = FrontmatterParser.date(forKey: "publishDate", in: content)
        self.tags = FrontmatterParser.stringArray(forKey: "tags", in: content)
        self.categories = FrontmatterParser.stringArray(forKey: "categories", in: content)
        self.searchTitle = self.title.lowercased()
        self.searchSlug = self.slug.lowercased()
    }

    /// Content-root-relative document path that Hugo's ref/relref resolve,
    /// e.g. "/posts/2024-06-20-my-post.md" or "/posts/my-bundle/index.md".
    /// Nil when the item lies outside the content root.
    func relrefPath(contentRoot: URL) -> String? {
        let filePath = url.standardizedFileURL.path
        let rootPath = contentRoot.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return nil }
        return String(filePath.dropFirst(rootPath.count))
    }

    enum PublishStatus {
        case draft
        case scheduled
        case published
    }

    /// Hugo's view of this post: drafts and future-dated posts don't render
    /// in a default build (mirrors `hugo list drafts` / `hugo list future`).
    var publishStatus: PublishStatus {
        if isDraft { return .draft }
        if let effectiveDate = publishDate ?? date, effectiveDate > Date() {
            return .scheduled
        }
        return .published
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

    fileprivate static func parseDate(from content: String) -> Date? {
        FrontmatterParser.date(forKey: "date", in: content)
    }

}
