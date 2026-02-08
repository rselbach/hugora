import Foundation
import Combine
import AppKit
import os

final class EditorState: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "EditorState"
    )
    @Published var currentItem: ContentItem?
    @Published var content: String = ""
    @Published var isDirty: Bool = false
    @Published var cursorPosition: Int = 0
    @Published var scrollPosition: CGFloat = 0

    private let sessionKey = "hugora.session.currentPost"
    private var entityMappings: [HTMLEntityMapping] = []

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
            let decoded = HTMLEntityCodec.decode(rawContent)
            currentItem = item
            content = decoded.decoded
            entityMappings = decoded.mappings
            isDirty = false
            cursorPosition = 0
            scrollPosition = 0
            saveSession()
        } catch {
            NSApp.presentError(error)
        }
    }

    func updateContent(_ newContent: String) {
        updateEntityMappings(oldText: content, newText: newContent)
        content = newContent
        isDirty = true
    }

    func save() {
        guard let item = currentItem, isDirty else { return }
        do {
            let encodedContent = HTMLEntityCodec.encode(content, mappings: entityMappings)
            let newURL = try saveWithRename(
                item: item,
                displayContent: content,
                saveContent: encodedContent
            )
            if newURL != item.url {
                currentItem = ContentItem(url: newURL, format: item.format, section: item.section)
                saveSession()
            }
            isDirty = false
        } catch {
            NSApp.presentError(error)
        }
    }

    private func saveWithRename(
        item: ContentItem,
        displayContent: String,
        saveContent: String
    ) throws -> URL {
        guard autoRenameOnSave else {
            try saveContent.data(using: .utf8)?.write(to: item.url)
            return item.url
        }

        let slug = deriveSlug(from: displayContent)
        let datePrefix = deriveDatePrefix(from: displayContent, fallback: item.date)
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

        try saveContent.data(using: .utf8)?.write(to: finalURL)
        return finalURL
    }

    private func deriveSlug(from content: String) -> String {
        if let slugValue = parseFrontmatterValue(key: "slug", from: content),
           let cleaned = cleanedSlugComponent(from: slugValue) {
            return cleaned
        }

        if let urlValue = parseFrontmatterValue(key: "url", from: content),
           let cleaned = cleanedSlugComponent(from: urlValue) {
            return cleaned
        }

        if let title = parseFrontmatterValue(key: "title", from: content) {
            return slugify(title)
        }
        
        return "untitled"
    }

    private func cleanedSlugComponent(from value: String) -> String? {
        let trimmed = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lastComponent = trimmed.components(separatedBy: "/").last ?? trimmed
        let cleaned = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
            let decoded = HTMLEntityCodec.decode(rawContent)
            currentItem = ContentItem(url: url, format: format, section: section)
            content = decoded.decoded
            entityMappings = decoded.mappings
            isDirty = false
        } catch {
            // Silently fail on restore
        }
    }

    private func extractSectionFromPath(_ url: URL) -> String {
        // Path like: .../content/blog/2025-01-01-post/index.md
        // We want "blog"
        let components = url.pathComponents
        if let contentIdx = components.lastIndex(of: "content"), contentIdx + 1 < components.count {
            let nextComponent = components[contentIdx + 1]
            let ext = (nextComponent as NSString).pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                return "(root)"
            }
            return nextComponent
        }
        return "unknown"
    }
}

private extension EditorState {
    var autoRenameOnSave: Bool {
        UserDefaults.standard.object(forKey: "autoRenameOnSave") as? Bool ?? false
    }
}

private struct TextChange {
    let oldRange: NSRange
    let newRange: NSRange
}

private func computeTextChange(oldText: String, newText: String) -> TextChange? {
    if oldText == newText { return nil }

    let oldString = oldText as NSString
    let newString = newText as NSString
    let oldLength = oldString.length
    let newLength = newString.length
    let minLength = min(oldLength, newLength)

    var prefixLength = 0
    while prefixLength < minLength,
          oldString.character(at: prefixLength) == newString.character(at: prefixLength) {
        prefixLength += 1
    }

    var suffixLength = 0
    let oldRemaining = oldLength - prefixLength
    let newRemaining = newLength - prefixLength
    let maxSuffix = min(oldRemaining, newRemaining)
    while suffixLength < maxSuffix,
          oldString.character(at: oldLength - 1 - suffixLength) ==
          newString.character(at: newLength - 1 - suffixLength) {
        suffixLength += 1
    }

    let oldRange = NSRange(location: prefixLength, length: oldLength - prefixLength - suffixLength)
    let newRange = NSRange(location: prefixLength, length: newLength - prefixLength - suffixLength)
    return TextChange(oldRange: oldRange, newRange: newRange)
}

private extension EditorState {
    func updateEntityMappings(oldText: String, newText: String) {
        guard let change = computeTextChange(oldText: oldText, newText: newText) else { return }
        guard !entityMappings.isEmpty else { return }

        let delta = change.newRange.length - change.oldRange.length
        let changeEnd = change.oldRange.location + change.oldRange.length

        var updatedMappings: [HTMLEntityMapping] = []
        for mapping in entityMappings {
            let mappingRange = mapping.decodedRange
            if changeOverlapsMapping(changeRange: change.oldRange, mappingRange: mappingRange) {
                continue
            }

            var newRange = mappingRange
            if mappingRange.location >= changeEnd {
                newRange.location += delta
            }

            updatedMappings.append(HTMLEntityMapping(
                decodedRange: newRange,
                encodedText: mapping.encodedText,
                decodedText: mapping.decodedText
            ))
        }

        entityMappings = updatedMappings
    }
}

private func changeOverlapsMapping(changeRange: NSRange, mappingRange: NSRange) -> Bool {
    if changeRange.length > 0 {
        return NSIntersectionRange(changeRange, mappingRange).length > 0
    }

    let changeLocation = changeRange.location
    let mappingStart = mappingRange.location
    let mappingEnd = mappingRange.location + mappingRange.length
    return changeLocation > mappingStart && changeLocation < mappingEnd
}
