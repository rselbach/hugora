import Foundation
import os

/// A value that can be written into frontmatter.
enum FrontmatterValue: Equatable {
    case string(String)
    case bool(Bool)
    case stringArray([String])
    /// Written verbatim (unquoted) — for dates and other typed scalars.
    case raw(String)
}

/// Rewrites individual keys inside a document's frontmatter while leaving
/// everything else untouched.
///
/// YAML and TOML are edited line-surgically so comments, ordering, and the
/// body survive byte-for-byte; only the edited key's lines change (block
/// arrays are rewritten in inline style). JSON frontmatter is re-serialized,
/// which normalizes key order.
enum FrontmatterRewriter {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "FrontmatterRewriter"
    )

    /// Returns the document with `key` set to `value` in its frontmatter,
    /// replacing an existing entry or appending before the closing
    /// delimiter. Returns nil when the document has no frontmatter or the
    /// rewrite fails.
    static func set(_ key: String, to value: FrontmatterValue, in text: String) -> String? {
        rewrite(text) { format, payload in
            switch format {
            case .yaml:
                return replaceOrAppend(
                    key: key,
                    renderedLine: "\(key): \(render(value, format: .yaml))",
                    in: payload,
                    format: .yaml
                )
            case .toml:
                return replaceOrAppend(
                    key: key,
                    renderedLine: "\(key) = \(render(value, format: .toml))",
                    in: payload,
                    format: .toml
                )
            case .json:
                return setJSONKey(key, to: value, in: payload)
            }
        }
    }

    /// Returns the document with `key` removed from its frontmatter, or nil
    /// when the document has no frontmatter or the rewrite fails. Removing
    /// an absent key returns the document unchanged.
    static func remove(_ key: String, in text: String) -> String? {
        rewrite(text) { format, payload in
            switch format {
            case .yaml, .toml:
                var lines = payload.components(separatedBy: "\n")
                guard let range = existingKeyLines(for: key, in: lines, format: format) else {
                    return payload
                }
                lines.removeSubrange(range)
                return lines.joined(separator: "\n")
            case .json:
                return setJSONKey(key, to: nil, in: payload)
            }
        }
    }

    // MARK: - Shared plumbing

    private static func rewrite(
        _ text: String,
        transform: (FrontmatterFormat, String) -> String?
    ) -> String? {
        guard let detected = detectFrontmatter(in: text) else { return nil }
        let nsText = text as NSString

        let payloadRange: NSRange
        switch detected.format {
        case .yaml, .toml:
            let start = NSMaxRange(detected.openingDelimiterRange)
            let end = detected.closingDelimiterRange.location
            guard end >= start else { return nil }
            payloadRange = NSRange(location: start, length: end - start)
        case .json:
            payloadRange = detected.range
        }

        let payload = nsText.substring(with: payloadRange)
        guard let newPayload = transform(detected.format, payload) else { return nil }
        return nsText.replacingCharacters(in: payloadRange, with: newPayload)
    }

    /// Finds the line range occupied by `key` (including continuation lines
    /// of block arrays / multi-line values), or nil when absent.
    private static func existingKeyLines(
        for key: String,
        in lines: [String],
        format: FrontmatterFormat
    ) -> Range<Int>? {
        for (index, line) in lines.enumerated() {
            guard keyDeclared(on: line, key: key, format: format) else { continue }
            var end = index + 1

            switch format {
            case .yaml:
                // Consume indented continuations and block-sequence items
                // (which may be zero-indented in YAML).
                while end < lines.count {
                    let next = lines[end]
                    let trimmed = next.trimmingCharacters(in: .whitespaces)
                    let isContinuation =
                        (next.hasPrefix(" ") || next.hasPrefix("\t")) && !trimmed.isEmpty
                    let isSequenceItem = trimmed.hasPrefix("- ") || trimmed == "-"
                    guard isContinuation || isSequenceItem else { break }
                    end += 1
                }
            case .toml:
                // Consume lines until brackets balance (multi-line arrays).
                var depth = bracketDelta(of: line)
                while depth > 0 && end < lines.count {
                    depth += bracketDelta(of: lines[end])
                    end += 1
                }
            case .json:
                break
            }

            return index..<end
        }
        return nil
    }

    private static func keyDeclared(on line: String, key: String, format: FrontmatterFormat) -> Bool {
        // Top-level keys only: nested YAML/TOML values are indented.
        guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { return false }
        let separator: Character = format == .toml ? "=" : ":"
        guard let separatorIndex = line.firstIndex(of: separator) else { return false }
        let declared = line[..<separatorIndex].trimmingCharacters(in: .whitespaces)
        return declared.caseInsensitiveCompare(key) == .orderedSame
    }

    private static func bracketDelta(of line: String) -> Int {
        var delta = 0
        var inString = false
        var escaped = false
        for char in line {
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                continue
            }
            switch char {
            case "\"": inString = true
            case "[": delta += 1
            case "]": delta -= 1
            default: break
            }
        }
        return delta
    }

    private static func replaceOrAppend(
        key: String,
        renderedLine: String,
        in payload: String,
        format: FrontmatterFormat
    ) -> String {
        var lines = payload.components(separatedBy: "\n")

        if let range = existingKeyLines(for: key, in: lines, format: format) {
            lines.replaceSubrange(range, with: [renderedLine])
            return lines.joined(separator: "\n")
        }

        // Append before the closing delimiter: the payload ends with the
        // newline that precedes it, so insert as the last non-empty line.
        if let lastNonEmpty = lines.lastIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            lines.insert(renderedLine, at: lastNonEmpty + 1)
        } else {
            lines.insert(renderedLine, at: 0)
        }
        return lines.joined(separator: "\n")
    }

    private static func render(_ value: FrontmatterValue, format: FrontmatterFormat) -> String {
        switch value {
        case .string(let string):
            return quoted(string)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .stringArray(let items):
            return "[" + items.map(quoted).joined(separator: ", ") + "]"
        case .raw(let raw):
            return raw
        }
    }

    private static func quoted(_ string: String) -> String {
        let escaped =
            string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - JSON

    /// Sets (or removes, when `value` is nil) a key in JSON frontmatter by
    /// re-serializing the object. Key order is normalized as a side effect.
    private static func setJSONKey(_ key: String, to value: FrontmatterValue?, in payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
            var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            logger.error("Failed to parse JSON frontmatter for rewrite")
            return nil
        }

        let existingKey = object.keys.first { $0.caseInsensitiveCompare(key) == .orderedSame } ?? key
        switch value {
        case .string(let string):
            object[existingKey] = string
        case .bool(let bool):
            object[existingKey] = bool
        case .stringArray(let items):
            object[existingKey] = items
        case .raw(let raw):
            object[existingKey] = raw
        case nil:
            object.removeValue(forKey: existingKey)
        }

        guard
            let newData = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let rendered = String(data: newData, encoding: .utf8)
        else {
            logger.error("Failed to serialize JSON frontmatter after rewrite")
            return nil
        }
        return rendered
    }
}
