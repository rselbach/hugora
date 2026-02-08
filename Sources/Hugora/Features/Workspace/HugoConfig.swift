import Foundation
import os

struct HugoConfig {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "HugoConfig"
    )
    let contentDir: String
    let archetypeDir: String
    let title: String?

    static let `default` = HugoConfig(contentDir: "content", archetypeDir: "archetypes", title: nil)

    static func load(from siteURL: URL) -> HugoConfig {
        // Priority order for config files
        let configFiles = [
            "hugo.toml", "hugo.yaml", "hugo.json",
            "config.toml", "config.yaml", "config.json",
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

    private static func parseTOML(_ content: String) -> HugoConfig {
        // Match: key = "value" or key = 'value'
        func extract(_ key: String) -> String? {
            let pattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*["']([^"']*)["']"#
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
            } catch {
                logger.error("Failed to compile TOML regex for key '\(key)': \(error.localizedDescription)")
                return nil
            }
            let range = NSRange(content.startIndex..., in: content)
            guard let match = regex.firstMatch(in: content, range: range),
                  let valueRange = Range(match.range(at: 1), in: content)
            else {
                return nil
            }
            return String(content[valueRange])
        }

        return HugoConfig(
            contentDir: extract("contentDir") ?? "content",
            archetypeDir: extract("archetypeDir") ?? "archetypes",
            title: extract("title")
        )
    }

    private static func parseYAML(_ content: String) -> HugoConfig {
        // Match: key: "value" or key: 'value' or key: value (unquoted)
        func extract(_ key: String) -> String? {
            let pattern = #"^\s*"# + NSRegularExpression.escapedPattern(for: key) + #"\s*:\s*["']?([^"'\n]+?)["']?\s*$"#
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)
            } catch {
                logger.error("Failed to compile YAML regex for key '\(key)': \(error.localizedDescription)")
                return nil
            }
            let range = NSRange(content.startIndex..., in: content)
            guard let match = regex.firstMatch(in: content, range: range),
                  let valueRange = Range(match.range(at: 1), in: content)
            else {
                return nil
            }
            return String(content[valueRange]).trimmingCharacters(in: .whitespaces)
        }

        return HugoConfig(
            contentDir: extract("contentDir") ?? "content",
            archetypeDir: extract("archetypeDir") ?? "archetypes",
            title: extract("title")
        )
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

        return HugoConfig(
            contentDir: json["contentDir"] as? String ?? "content",
            archetypeDir: json["archetypeDir"] as? String ?? "archetypes",
            title: json["title"] as? String
        )
    }
}
