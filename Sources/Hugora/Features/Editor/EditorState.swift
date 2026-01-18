import Foundation
import Combine
import AppKit

private let htmlEntityPattern = try! NSRegularExpression(pattern: "&#(\\d+);|&#x([0-9A-Fa-f]+);|&([a-zA-Z]+);")

private let namedEntities: [String: String] = [
    "quot": "\"", "amp": "&", "apos": "'", "lt": "<", "gt": ">",
    "nbsp": "\u{00A0}", "iexcl": "¡", "cent": "¢", "pound": "£", "curren": "¤",
    "yen": "¥", "brvbar": "¦", "sect": "§", "uml": "¨", "copy": "©",
    "ordf": "ª", "laquo": "«", "not": "¬", "shy": "\u{00AD}", "reg": "®",
    "macr": "¯", "deg": "°", "plusmn": "±", "sup2": "²", "sup3": "³",
    "acute": "´", "micro": "µ", "para": "¶", "middot": "·", "cedil": "¸",
    "sup1": "¹", "ordm": "º", "raquo": "»", "frac14": "¼", "frac12": "½",
    "frac34": "¾", "iquest": "¿", "times": "×", "divide": "÷",
    "ndash": "–", "mdash": "—", "lsquo": "'", "rsquo": "'", "sbquo": "‚",
    "ldquo": "\u{201C}", "rdquo": "\u{201D}", "bdquo": "„", "dagger": "†", "Dagger": "‡",
    "bull": "•", "hellip": "…", "permil": "‰", "prime": "′", "Prime": "″",
    "lsaquo": "‹", "rsaquo": "›", "oline": "‾", "frasl": "⁄", "euro": "€",
    "trade": "™", "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓",
    "harr": "↔", "spades": "♠", "clubs": "♣", "hearts": "♥", "diams": "♦"
]

func decodeHTMLEntities(_ string: String) -> String {
    let range = NSRange(string.startIndex..., in: string)
    var result = string

    let matches = htmlEntityPattern.matches(in: string, range: range).reversed()
    for match in matches {
        var replacement: String?

        if let decRange = Range(match.range(at: 1), in: string),
           let codePoint = UInt32(string[decRange]),
           let scalar = Unicode.Scalar(codePoint) {
            replacement = String(Character(scalar))
        } else if let hexRange = Range(match.range(at: 2), in: string),
                  let codePoint = UInt32(string[hexRange], radix: 16),
                  let scalar = Unicode.Scalar(codePoint) {
            replacement = String(Character(scalar))
        } else if let nameRange = Range(match.range(at: 3), in: string) {
            replacement = namedEntities[String(string[nameRange])]
        }

        if let replacement, let matchRange = Range(match.range, in: result) {
            result.replaceSubrange(matchRange, with: replacement)
        }
    }

    return result
}

final class EditorState: ObservableObject {
    @Published var currentItem: ContentItem?
    @Published var content: String = ""
    @Published var isDirty: Bool = false
    @Published var cursorPosition: Int = 0
    @Published var scrollPosition: CGFloat = 0

    private let sessionKey = "hugora.session.currentPost"

    var title: String {
        currentItem?.title ?? "No Document Selected"
    }

    init() {
        restoreSession()
    }

    func openItem(_ item: ContentItem) {
        saveCurrentIfDirty()

        do {
            let rawContent = try String(contentsOf: item.url, encoding: .utf8)
            let decodedContent = decodeHTMLEntities(rawContent)
            currentItem = item
            content = decodedContent
            isDirty = rawContent != decodedContent
            cursorPosition = 0
            scrollPosition = 0
            saveSession()
        } catch {
            NSApp.presentError(error)
        }
    }

    func updateContent(_ newContent: String) {
        content = newContent
        isDirty = true
    }

    func save() {
        guard let item = currentItem, isDirty else { return }
        do {
            let newURL = try saveWithRename(item: item, content: content)
            if newURL != item.url {
                currentItem = ContentItem(url: newURL, format: item.format, section: item.section)
                saveSession()
            }
            isDirty = false
        } catch {
            NSApp.presentError(error)
        }
    }

    private func saveWithRename(item: ContentItem, content: String) throws -> URL {
        let slug = deriveSlug(from: content)
        let datePrefix = deriveDatePrefix(from: content, fallback: item.date)
        let expectedName = "\(datePrefix)-\(slug)"
        
        let fm = FileManager.default
        var finalURL = item.url

        switch item.format {
        case .bundle:
            let currentFolder = item.url.deletingLastPathComponent()
            let currentFolderName = currentFolder.lastPathComponent
            
            if currentFolderName != expectedName {
                let parentDir = currentFolder.deletingLastPathComponent()
                let newFolder = parentDir.appendingPathComponent(expectedName)
                
                if !fm.fileExists(atPath: newFolder.path) {
                    try fm.moveItem(at: currentFolder, to: newFolder)
                    finalURL = newFolder.appendingPathComponent("index.md")
                }
            }
            
        case .file:
            let currentFileName = item.url.deletingPathExtension().lastPathComponent
            
            if currentFileName != expectedName {
                let parentDir = item.url.deletingLastPathComponent()
                let newFile = parentDir.appendingPathComponent("\(expectedName).md")
                
                if !fm.fileExists(atPath: newFile.path) {
                    try fm.moveItem(at: item.url, to: newFile)
                    finalURL = newFile
                }
            }
        }

        try content.data(using: .utf8)?.write(to: finalURL)
        return finalURL
    }

    private func deriveSlug(from content: String) -> String {
        if let urlValue = parseFrontmatterValue(key: "url", from: content) {
            let cleaned = urlValue
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .components(separatedBy: "/")
                .last ?? urlValue
            return cleaned
        }
        
        if let title = parseFrontmatterValue(key: "title", from: content) {
            return slugify(title)
        }
        
        return "untitled"
    }

    private func deriveDatePrefix(from content: String, fallback: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let dateString = parseFrontmatterValue(key: "date", from: content) {
            return String(dateString.prefix(10))
        }
        
        if let date = fallback {
            return formatter.string(from: date)
        }
        
        return formatter.string(from: Date())
    }

    func saveCurrentIfDirty() {
        if isDirty {
            save()
        }
    }

    // MARK: - Session Persistence

    private func saveSession() {
        guard let item = currentItem else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        UserDefaults.standard.set(item.url.path, forKey: sessionKey)
    }

    private func restoreSession() {
        guard let path = UserDefaults.standard.string(forKey: sessionKey),
              FileManager.default.fileExists(atPath: path) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        let format: ContentFormat = url.lastPathComponent == "index.md" ? .bundle : .file
        let section = extractSectionFromPath(url)

        do {
            let rawContent = try String(contentsOf: url, encoding: .utf8)
            let decodedContent = decodeHTMLEntities(rawContent)
            currentItem = ContentItem(url: url, format: format, section: section)
            content = decodedContent
            isDirty = rawContent != decodedContent
        } catch {
            // Silently fail on restore
        }
    }

    private func extractSectionFromPath(_ url: URL) -> String {
        // Path like: .../content/blog/2025-01-01-post/index.md
        // We want "blog"
        let components = url.pathComponents
        if let contentIdx = components.lastIndex(of: "content"), contentIdx + 1 < components.count {
            return components[contentIdx + 1]
        }
        return "unknown"
    }
}
