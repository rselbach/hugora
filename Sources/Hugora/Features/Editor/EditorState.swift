import Foundation
import Combine
import AppKit
import os

enum EditorStateError: LocalizedError {
    case utf8EncodingFailed
    case renameTargetAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .utf8EncodingFailed:
            "Failed to encode document content as UTF-8."
        case .renameTargetAlreadyExists(let path):
            "Cannot rename because a file already exists at \(path)."
        }
    }
}

/// Manages the state of the currently open content item in the editor.
///
/// Handles loading, saving, and tracking changes to markdown content files.
/// Manages HTML entity encoding/decoding for special characters, automatic
/// file renaming based on frontmatter, and session persistence across app launches.
@MainActor
final class EditorState: ObservableObject {
    private enum Timing {
        /// How long the "Saved" indicator stays visible after a save.
        static let justSavedDuration: UInt64 = 2_000_000_000   // 2 s
        /// Delay before auto-saving after the user stops typing.
        static let autoSaveDelay: UInt64 = 1_000_000_000       // 1 s
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "EditorState"
    )

    /// The currently loaded content item.
    @Published var currentItem: ContentItem?

    /// The decoded markdown content (with HTML entities resolved).
    @Published var content: String = ""

    /// Whether the current content has unsaved changes.
    @Published var isDirty: Bool = false

    /// Whether a file operation (load/save) is in progress.
    @Published var isLoading: Bool = false

    /// Transient flag set to true for 2 seconds after a successful save.
    @Published var justSaved: Bool = false

    /// Current cursor position in the text (character offset).
    @Published var cursorPosition: Int = 0

    /// Current scroll position for restoring view state.
    @Published var scrollPosition: CGFloat = 0

    private static let datePrefixFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var entityMappings: [HTMLEntityMapping] = []
    private var openRevision: UInt64 = 0
    private var autoSaveTask: Task<Void, Never>?

    /// The display title of the current item, or placeholder if none selected.
    var title: String {
        currentItem?.title ?? "No Document Selected"
    }

    /// Initializes the editor state and restores the previous session if available.
    init() {
        restoreSession()
    }

    /// Opens a content item and loads its content into the editor.
    ///
    /// - Parameter item: The content item to open.
    /// - Note: Saves the current item if dirty before opening the new one.
    func openItem(_ item: ContentItem) {
        saveCurrentIfDirty()
        autoSaveTask?.cancel()
        autoSaveTask = nil
        openRevision &+= 1
        let capturedRevision = openRevision
        isLoading = true
        currentItem = item
        content = ""
        entityMappings = []
        isDirty = false
        cursorPosition = 0
        scrollPosition = 0

        Task(priority: .userInitiated) {
            do {
                let rawContent = try await Task.detached {
                    try String(contentsOf: item.url, encoding: .utf8)
                }.value
                let decoded = HTMLEntityCodec.decode(rawContent)
                guard self.openRevision == capturedRevision,
                      self.currentItem?.url == item.url else {
                    return
                }
                self.currentItem = item
                self.content = decoded.decoded
                self.entityMappings = decoded.mappings
                self.isDirty = false
                self.isLoading = false
                self.cursorPosition = 0
                self.scrollPosition = 0
                self.saveSession()
            } catch {
                guard self.openRevision == capturedRevision else { return }
                Self.logger.error("Failed to open file \(item.url.lastPathComponent): \(error.localizedDescription)")
                self.isLoading = false
                Self.presentError(error)
            }
        }
    }

    /// Updates the editor content and marks it as dirty.
    ///
    /// Also updates HTML entity mappings to preserve them during edits.
    ///
    /// - Parameter newContent: The new content string.
    func updateContent(_ newContent: String) {
        guard newContent != content else { return }
        openRevision &+= 1
        if isLoading {
            isLoading = false
        }
        updateEntityMappings(oldText: content, newText: newContent)
        content = newContent
        isDirty = true
        scheduleAutoSaveIfNeeded()
    }

    /// Saves the current content to disk.
    ///
    /// Encodes HTML entities back to their escaped form, optionally renames
    /// the file based on frontmatter (if auto-rename is enabled), and updates
    /// session state.
    ///
    /// - Note: No-op if no item is loaded or content is not dirty.
    func save() {
        guard let item = currentItem, isDirty else { return }
        autoSaveTask?.cancel()
        autoSaveTask = nil
        isLoading = true
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
            isLoading = false
            justSaved = true
            Task { @MainActor in
                do { try await Task.sleep(nanoseconds: Timing.justSavedDuration) }
                catch { return } // task cancelled
                self.justSaved = false
            }
        } catch {
            Self.logger.error("Failed to save file \(item.url.lastPathComponent): \(error.localizedDescription)")
            isLoading = false
            Self.presentError(error)
        }
    }

    private func saveWithRename(
        item: ContentItem,
        displayContent: String,
        saveContent: String
    ) throws -> URL {
        guard let saveData = saveContent.data(using: .utf8) else {
            throw EditorStateError.utf8EncodingFailed
        }

        guard autoRenameOnSave else {
            try saveData.write(to: item.url)
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
                
                if fm.fileExists(atPath: newFolder.path) {
                    throw EditorStateError.renameTargetAlreadyExists(newFolder.path)
                }
                try fm.moveItem(at: currentFolder, to: newFolder)
                finalURL = newFolder.appendingPathComponent("index.md")
            }
            
        case .file:
            let currentFileName = item.url.deletingPathExtension().lastPathComponent
            
            if currentFileName != expectedName {
                let parentDir = item.url.deletingLastPathComponent()
                let newFile = parentDir.appendingPathComponent("\(expectedName).md")
                
                if fm.fileExists(atPath: newFile.path) {
                    throw EditorStateError.renameTargetAlreadyExists(newFile.path)
                }
                try fm.moveItem(at: item.url, to: newFile)
                finalURL = newFile
            }
        }

        try saveData.write(to: finalURL)
        return finalURL
    }

    private func deriveSlug(from content: String) -> String {
        if let slugValue = FrontmatterParser.value(forKey: "slug", in: content),
           let cleaned = cleanedSlugComponent(from: slugValue) {
            return cleaned
        }

        if let urlValue = FrontmatterParser.value(forKey: "url", in: content),
           let cleaned = cleanedSlugComponent(from: urlValue) {
            return cleaned
        }

        if let title = FrontmatterParser.value(forKey: "title", in: content) {
            return Slug.from(title)
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
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return nil }
        return cleaned
    }

    private func deriveDatePrefix(from content: String, fallback: Date?) -> String {
        if let dateString = FrontmatterParser.value(forKey: "date", in: content) {
            return String(dateString.prefix(10))
        }

        if let date = fallback {
            return Self.datePrefixFormatter.string(from: date)
        }

        return Self.datePrefixFormatter.string(from: Date())
    }

    private func scheduleAutoSaveIfNeeded() {
        guard autoSaveEnabled else {
            autoSaveTask?.cancel()
            autoSaveTask = nil
            return
        }

        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Timing.autoSaveDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, self.isDirty else { return }
            self.save()
        }
    }

    /// Saves the current item if it has unsaved changes.
    ///
    /// Convenience method for saving before opening another file or closing.
    func saveCurrentIfDirty() {
        if isDirty {
            save()
        }
    }

    // MARK: - Session Persistence

    private func saveSession() {
        guard let item = currentItem else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.sessionCurrentPost)
            return
        }
        UserDefaults.standard.set(item.url.path, forKey: DefaultsKey.sessionCurrentPost)
    }

    private func restoreSession() {
        guard let path = UserDefaults.standard.string(forKey: DefaultsKey.sessionCurrentPost),
              FileManager.default.fileExists(atPath: path) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard isSessionPathAllowed(url) else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.sessionCurrentPost)
            return
        }
        let format: ContentFormat = ContentFile.isLeafBundleIndex(url) ? .bundle : .file
        let section = extractSectionFromPath(url)

        Task(priority: .utility) {
            do {
                let rawContent = try await Task.detached {
                    try String(contentsOf: url, encoding: .utf8)
                }.value
                let decoded = HTMLEntityCodec.decode(rawContent)
                self.currentItem = ContentItem(url: url, format: format, section: section, content: rawContent)
                self.content = decoded.decoded
                self.entityMappings = decoded.mappings
                self.isDirty = false
            } catch {
                Self.logger.error("Failed to restore session file \(url.lastPathComponent): \(error.localizedDescription)")
                Task { @MainActor in
                    Self.presentError(error)
                }
            }
        }
    }

    private static func presentError(_ error: Error) {
        guard NSApp != nil else {
            logger.error("Unable to present error (NSApp unavailable): \(error.localizedDescription)")
            return
        }
        NSApp.presentError(error)
    }

    private func isSessionPathAllowed(_ fileURL: URL) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.workspaceBookmark) else {
            Self.logger.error("Session restore skipped: no workspace bookmark is available")
            return false
        }

        var isStale = false
        do {
            let workspaceURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let standardizedFile = fileURL.standardizedFileURL
            return PathSafety.isSameOrDescendant(standardizedFile, of: workspaceURL.standardizedFileURL)
        } catch {
            Self.logger.error("Session restore skipped: failed to resolve workspace bookmark: \(error.localizedDescription)")
            return false
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
    var autoSaveEnabled: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.autoSaveEnabled) as? Bool ?? true
    }

    var autoRenameOnSave: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.autoRenameOnSave) as? Bool ?? false
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
