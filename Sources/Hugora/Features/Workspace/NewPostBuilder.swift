import Foundation

struct NewPostBuilder {
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
            return render(template: template, title: title, slug: slug, sectionName: normalizedSection, date: date)
        }

        return defaultFrontmatter(title: title, date: date)
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
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }

        return nil
    }

    private func archetypeBaseURL() -> URL {
        let expanded = (config.archetypeDir as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return siteURL.appendingPathComponent(expanded)
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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
