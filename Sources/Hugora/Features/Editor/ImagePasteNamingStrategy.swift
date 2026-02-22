import Foundation

enum ImagePasteNamingStrategy: String, CaseIterable, Identifiable, Codable {
    case timestamp
    case uuid
    case postSlugTimestamp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .timestamp:
            return "Timestamp"
        case .uuid:
            return "UUID"
        case .postSlugTimestamp:
            return "Post slug + time"
        }
    }

    static func current() -> ImagePasteNamingStrategy {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.imagePasteNamingStrategy) ?? ImagePasteNamingStrategy.timestamp.rawValue
        return ImagePasteNamingStrategy(rawValue: raw) ?? .timestamp
    }
}
