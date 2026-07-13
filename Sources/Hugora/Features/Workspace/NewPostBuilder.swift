import Foundation
import os

struct NewPostBuilder {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "NewPostBuilder"
    )
    let siteURL: URL
    let config: HugoConfig
    let fileManager: FileManager

    init(siteURL: URL, config: HugoConfig, fileManager: FileManager = .default) {
        self.siteURL = siteURL
        self.config = config
        self.fileManager = fileManager
    }

    func buildContent(
        sectionName: String?,
        format: ContentFormat,
        title: String,
        slug: String,
        date: Date
    ) -> String {
        let normalizedSection = normalizeSection(sectionName)
        if let template = loadArchetype(sectionName: normalizedSection, format: format) {
            let rendered = render(template: template, title: title, slug: slug, sectionName: normalizedSection, date: date)
            if isRenderedTemplateUsable(rendered) {
                return rendered
            }
            Self.logger.warning(
                "Archetype uses template constructs the built-in renderer doesn't support; using default front matter instead"
            )
        }

        return defaultFrontmatter(title: title, date: date)
    }

    /// A rendered archetype is only usable if it produced valid front matter
    /// with a title and date and left no Go template actions behind.
    /// Hugo's own stock default.md uses functions like `replace` that the
    /// token renderer can't evaluate; treat that as "no archetype" rather
    /// than failing post creation.
    private func isRenderedTemplateUsable(_ content: String) -> Bool {
        guard detectFrontmatterBlock(in: content) != nil,
              FrontmatterParser.value(forKey: "title", in: content) != nil,
              FrontmatterParser.date(forKey: "date", in: content) != nil else {
            return false
        }
        return !containsUnrenderedTemplateAction(content)
    }

    /// Detects leftover `{{ ... }}` Go template actions, ignoring Hugo
    /// shortcodes (`{{<`, `{{%`) which are legitimate post content.
    private func containsUnrenderedTemplateAction(_ content: String) -> Bool {
        var search = content.startIndex
        while let open = content.range(of: "{{", range: search..<content.endIndex) {
            let next = open.upperBound
            if next < content.endIndex, content[next] == "<" || content[next] == "%" {
                search = next
                continue
            }
            return true
        }
        return false
    }

    private func normalizeSection(_ sectionName: String?) -> String? {
        guard let sectionName, !sectionName.isEmpty else { return nil }
        if sectionName == "(root)" { return nil }
        return sectionName
    }

    private func loadArchetype(sectionName: String?, format: ContentFormat) -> String? {
        let baseURL = archetypeBaseURL()
        let candidates = archetypeCandidates(baseURL: baseURL, sectionName: sectionName, format: format)

        for url in candidates {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                Self.logger.error("Failed to read archetype \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return nil
    }

    private func archetypeBaseURL() -> URL {
        let dir = config.archetypeDir
        let candidate = siteURL.appendingPathComponent(dir).standardizedFileURL
        guard PathSafety.isSameOrDescendant(candidate, of: siteURL) else {
            return siteURL.appendingPathComponent("archetypes")
        }
        return candidate
    }

    private func archetypeCandidates(
        baseURL: URL,
        sectionName: String?,
        format: ContentFormat
    ) -> [URL] {
        var candidates: [URL] = []

        if let sectionName {
            if format == .bundle {
                candidates.append(baseURL.appendingPathComponent(sectionName).appendingPathComponent("index.md"))
            }
            candidates.append(baseURL.appendingPathComponent("\(sectionName).md"))
            if format == .file {
                candidates.append(baseURL.appendingPathComponent(sectionName).appendingPathComponent("index.md"))
            }
        }

        candidates.append(baseURL.appendingPathComponent("default.md"))
        return candidates
    }

    // Local time with offset, like `hugo new` writes. Keeping this in the
    // local zone means the yyyy-MM-dd folder prefix (also local) and the
    // frontmatter date can never disagree across midnight.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private func render(
        template: String,
        title: String,
        slug: String,
        sectionName: String?,
        date: Date
    ) -> String {
        let dateString = Self.isoFormatter.string(from: date)

        let typeValue = sectionName ?? ""
        var rendered = template
        rendered = replaceToken(in: rendered, token: ".Title", value: title)
        rendered = replaceToken(in: rendered, token: ".Date", value: dateString)
        rendered = replaceToken(in: rendered, token: ".Slug", value: slug)
        rendered = replaceToken(in: rendered, token: ".Type", value: typeValue)
        rendered = replaceToken(in: rendered, token: ".Section", value: typeValue)
        return rendered
    }

    private func replaceToken(in template: String, token: String, value: String) -> String {
        let variants = [
            "{{ \(token) }}",
            "{{\(token)}}"
        ]
        return variants.reduce(template) { partial, variant in
            partial.replacingOccurrences(of: variant, with: value)
        }
    }

    private func defaultFrontmatter(title: String, date: Date) -> String {
        let dateString = Self.isoFormatter.string(from: date)

        return """
        ---
        title: "\(title)"
        date: \(dateString)
        draft: true
        ---

        """
    }
}
