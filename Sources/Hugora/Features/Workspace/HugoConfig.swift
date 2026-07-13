import Foundation
import os
import TOMLKit
import Yams

struct HugoConfig {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "HugoConfig"
    )
    let contentDir: String
    let archetypeDir: String
    let title: String?
    let themes: [String]

    init(contentDir: String, archetypeDir: String, title: String?, themes: [String] = []) {
        self.contentDir = contentDir
        self.archetypeDir = archetypeDir
        self.title = title
        self.themes = themes
    }

    static let `default` = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)

    static func load(from siteURL: URL) -> HugoConfig {
        // Priority order for config files
        let configFiles = [
            "hugo.toml", "hugo.yaml", "hugo.yml", "hugo.json",
            "config.toml", "config.yaml", "config.yml", "config.json",
        ]

        // Try root config files first
        for filename in configFiles {
            let fileURL = siteURL.appendingPathComponent(filename)
            if let config = parse(fileAt: fileURL) {
                return config
            }
        }

        // Try config/_default/ directory
        let configDir = siteURL.appendingPathComponent("config/_default")
        for filename in configFiles {
            let fileURL = configDir.appendingPathComponent(filename)
            if let config = parse(fileAt: fileURL) {
                return config
            }
        }

        return .default
    }

    private static func parse(fileAt url: URL) -> HugoConfig? {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            logger.error("Failed to read config \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "toml":
            return parseTOML(content)
        case "yaml", "yml":
            return parseYAML(content)
        case "json":
            return parseJSON(content)
        default:
            return nil
        }
    }

    private static func parseTOML(_ content: String) -> HugoConfig? {
        do {
            let table = try TOMLTable(string: content)
            let jsonString = table.convert(to: .json)
            guard let data = jsonString.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return config(from: object)
        } catch {
            logger.error("Failed to parse TOML config: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseYAML(_ content: String) -> HugoConfig? {
        do {
            guard let object = try Yams.load(yaml: content) as? [String: Any] else {
                return nil
            }
            return config(from: object)
        } catch {
            logger.error("Failed to parse YAML config: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseJSON(_ content: String) -> HugoConfig? {
        guard let data = content.data(using: .utf8) else {
            return nil
        }

        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            json = parsed
        } catch {
            logger.error("Failed to parse JSON config: \(error.localizedDescription)")
            return nil
        }

        return config(from: json)
    }

    private static func config(from object: [String: Any]) -> HugoConfig {
        let title = extractString("title", from: object)
        let contentDir = extractString("contentDir", from: object) ?? "content"
        let archetypeDir = extractString("archetypeDir", from: object) ?? "archetypes"

        return HugoConfig(
            contentDir: contentDir,
            archetypeDir: archetypeDir,
            title: title,
            themes: extractThemes(from: object)
        )
    }

    private static func extractString(_ key: String, from object: [String: Any]) -> String? {
        guard let entry = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) else {
            return nil
        }
        return entry.value as? String
    }

    /// Hugo's `theme` key is a string or an array of theme names.
    private static func extractThemes(from object: [String: Any]) -> [String] {
        guard let entry = object.first(where: { $0.key.caseInsensitiveCompare("theme") == .orderedSame }) else {
            return []
        }
        switch entry.value {
        case let name as String:
            return [name]
        case let names as [Any]:
            return names.compactMap { $0 as? String }
        default:
            return []
        }
    }
}
