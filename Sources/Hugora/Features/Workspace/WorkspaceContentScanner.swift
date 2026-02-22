import Foundation
import os

enum WorkspaceContentScanner {
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
                let items = collectItemsRecursively(
                    in: itemURL,
                    sectionName: sectionName,
                    contentRoot: contentDir
                ).sorted()
                let section = ContentSection(name: sectionName, url: itemURL, items: items)
                loadedSections.append(section)
            } else if ContentFile.isSupportedContentFile(itemURL) {
                rootItems.append(ContentItem(url: itemURL, format: .file, section: "(root)"))
            }
        }

        if !rootItems.isEmpty {
            let rootSection = ContentSection(name: "(root)", url: contentDir, items: rootItems.sorted())
            loadedSections.append(rootSection)
        }

        return loadedSections
    }

    private static func collectItemsRecursively(
        in directoryURL: URL,
        sectionName: String,
        contentRoot: URL
    ) -> [ContentItem] {
        let entries = listDirectoryEntries(at: directoryURL)

        if let leafIndex = preferredLeafBundleIndex(in: entries, contentRoot: contentRoot) {
            return [ContentItem(url: leafIndex, format: .bundle, section: sectionName)]
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
            items.append(ContentItem(url: entry, format: .file, section: sectionName))
        }

        return items
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
