import Foundation

enum ImagePasteLocation: String, CaseIterable, Identifiable {
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

    static func current() -> ImagePasteLocation {
        let raw = UserDefaults.standard.string(forKey: "imagePasteLocation") ?? ImagePasteLocation.pageFolder.rawValue
        return ImagePasteLocation(rawValue: raw) ?? .pageFolder
    }
}
