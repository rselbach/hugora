import Foundation

enum ImagePasteLocation: String, CaseIterable, Identifiable, Codable {
    case pageFolder
    case siteStatic
    case siteAssets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pageFolder:
            "Same Folder as Post"
        case .siteStatic:
            "Site Static Folder"
        case .siteAssets:
            "Site Assets Folder"
        }
    }

    static func current(siteURL: URL? = nil) -> ImagePasteLocation {
        if let workspaceLocation = WorkspacePreferenceStore.preferences(for: siteURL).imagePasteLocation {
            return workspaceLocation
        }
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.imagePasteLocation) ?? ImagePasteLocation.pageFolder.rawValue
        return ImagePasteLocation(rawValue: raw) ?? .pageFolder
    }
}
