import Foundation
import os

enum WorkspaceContentScanner {
    private static let metadataReadLimit = 16 * 1024

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "WorkspaceContentScanner"
    )

    static func collectContentSections(from contentDir: URL) -> [ContentSection] {
        let sectionDirs = listDirectoryEntries(at: contentDir)
        var loadedSections: [ContentSection] = []
        var rootItems: [ContentItem] = []

        for itemURL in sectionDirs {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try itemURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
            } catch {
                logger.error(
                    "Failed to read resource values for \(itemURL.lastPathComponent): \(error.localizedDescription)"
                )
                continue
            }
            if resourceValues.isSymbolicLink == true {
                continue
            }
            guard let isDir = resourceValues.isDirectory else {
                continue
            }

            if isDir {
                let sectionName = itemURL.lastPathComponent
                let items = collectSectionItems(in: itemURL, sectionName: sectionName, contentRoot: contentDir)
                let section = ContentSection(name: sectionName, url: itemURL, items: items)
                loadedSections.append(section)
            } else if ContentFile.isSupportedContentFile(itemURL) {
                rootItems.append(makeContentItem(url: itemURL, format: .file, section: "(root)"))
            }
        }

        if !rootItems.isEmpty {
            let rootSection = ContentSection(name: "(root)", url: contentDir, items: rootItems.sorted())
            loadedSections.append(rootSection)
        }

        return loadedSections
    }

    static func collectSectionItems(in sectionURL: URL, sectionName: String, contentRoot: URL) -> [ContentItem] {
        collectItemsRecursively(in: sectionURL, sectionName: sectionName, contentRoot: contentRoot).sorted()
    }

    static func collectRootItems(from contentDir: URL) -> [ContentItem] {
        listDirectoryEntries(at: contentDir)
            .compactMap { entry -> ContentItem? in
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true || values?.isSymbolicLink == true {
                    return nil
                }
                guard ContentFile.isSupportedContentFile(entry) else { return nil }
                return makeContentItem(url: entry, format: .file, section: "(root)")
            }
            .sorted()
    }

    private static func collectItemsRecursively(
        in directoryURL: URL,
        sectionName: String,
        contentRoot: URL
    ) -> [ContentItem] {
        let entries = listDirectoryEntries(at: directoryURL)

        if let leafIndex = preferredLeafBundleIndex(in: entries, contentRoot: contentRoot) {
            return [makeContentItem(url: leafIndex, format: .bundle, section: sectionName)]
        }

        var items: [ContentItem] = []
        for entry in entries {
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            } catch {
                logger.error(
                    "Failed to read resource values for \(entry.lastPathComponent): \(error.localizedDescription)"
                )
                continue
            }
            if values.isSymbolicLink == true {
                continue
            }

            guard let isDirectory = values.isDirectory else { continue }

            if isDirectory {
                let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
                guard PathSafety.isSameOrDescendant(resolved, of: contentRoot) else { continue }
                items.append(
                    contentsOf: collectItemsRecursively(
                        in: entry,
                        sectionName: sectionName,
                        contentRoot: contentRoot
                    )
                )
                continue
            }

            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            guard PathSafety.isSameOrDescendant(resolved, of: contentRoot) else { continue }
            guard ContentFile.isSupportedContentFile(entry) else { continue }
            items.append(makeContentItem(url: entry, format: .file, section: sectionName))
        }

        return items
    }

    private static func makeContentItem(url: URL, format: ContentFormat, section: String) -> ContentItem {
        guard let metadataWindow = loadMetadataWindow(from: url) else {
            return ContentItem(url: url, format: format, section: section)
        }

        if needsFullReadForMetadata(window: metadataWindow, url: url) {
            return ContentItem(url: url, format: format, section: section)
        }

        return ContentItem(url: url, format: format, section: section, content: metadataWindow)
    }

    private static func loadMetadataWindow(from url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                do {
                    try handle.close()
                } catch {
                    logger.error("Failed to close file handle for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            guard let data = try handle.read(upToCount: metadataReadLimit),
                  !data.isEmpty else {
                return ""
            }

            return String(data: data, encoding: .utf8)
        } catch {
            logger.error("Failed to read metadata window for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private static func needsFullReadForMetadata(window: String, url: URL) -> Bool {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > metadataReadLimit else {
            return false
        }

        let normalized = window.replacingOccurrences(of: "\r\n", with: "\n")

        if normalized.hasPrefix("---\n") {
            return !normalized.dropFirst(4).contains("\n---\n")
        }

        if normalized.hasPrefix("+++\n") {
            return !normalized.dropFirst(4).contains("\n+++\n")
        }

        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return !trimmed.contains("\n}")
        }

        return false
    }

    private static func preferredLeafBundleIndex(in entries: [URL], contentRoot: URL) -> URL? {
        entries.first { entry in
            guard ContentFile.isSupportedContentFile(entry) && ContentFile.isLeafBundleIndex(entry) else {
                return false
            }
            guard let values = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink != true else {
                return false
            }
            let resolved = entry.resolvingSymlinksInPath().standardizedFileURL
            return PathSafety.isSameOrDescendant(resolved, of: contentRoot)
        }
    }

    private static func listDirectoryEntries(at url: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.error("Failed to list directory \(url.lastPathComponent): \(error.localizedDescription)")
            return []
        }
    }
}
