import Foundation
import os

struct WorkspacePreferences: Codable, Equatable {
    var newPostFormat: ContentFormat?
    var preferredSection: String?
    var imagePasteLocation: ImagePasteLocation?
}

enum WorkspacePreferenceStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.selbach.hugora",
        category: "WorkspacePreferenceStore"
    )

    static func preferences(for siteURL: URL?) -> WorkspacePreferences {
        guard let siteURL else { return WorkspacePreferences() }
        let key = workspaceKey(for: siteURL)
        let map = loadMap()
        return map[key] ?? WorkspacePreferences()
    }

    static func setNewPostFormat(_ format: ContentFormat?, for siteURL: URL?) {
        update(for: siteURL) { preferences in
            preferences.newPostFormat = format
        }
    }

    static func setPreferredSection(_ section: String?, for siteURL: URL?) {
        update(for: siteURL) { preferences in
            preferences.preferredSection = section
        }
    }

    static func setImagePasteLocation(_ location: ImagePasteLocation?, for siteURL: URL?) {
        update(for: siteURL) { preferences in
            preferences.imagePasteLocation = location
        }
    }

    private static func update(for siteURL: URL?, mutate: (inout WorkspacePreferences) -> Void) {
        guard let siteURL else { return }
        let key = workspaceKey(for: siteURL)
        var map = loadMap()
        var preferences = map[key] ?? WorkspacePreferences()
        mutate(&preferences)

        if preferences == WorkspacePreferences() {
            map.removeValue(forKey: key)
        } else {
            map[key] = preferences
        }

        saveMap(map)
    }

    private static func workspaceKey(for siteURL: URL) -> String {
        siteURL.standardizedFileURL.path
    }

    private static func loadMap() -> [String: WorkspacePreferences] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.workspacePreferences) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: WorkspacePreferences].self, from: data)
        } catch {
            logger.error("Failed to decode workspace preferences: \(error.localizedDescription)")
            return [:]
        }
    }

    private static func saveMap(_ map: [String: WorkspacePreferences]) {
        do {
            let data = try JSONEncoder().encode(map)
            UserDefaults.standard.set(data, forKey: DefaultsKey.workspacePreferences)
        } catch {
            logger.error("Failed to encode workspace preferences: \(error.localizedDescription)")
        }
    }
}
