import Foundation

enum ImagePasteFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case jpeg

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .png:
            return "png"
        case .jpeg:
            return "jpg"
        }
    }

    var displayName: String {
        switch self {
        case .png:
            return "PNG (lossless)"
        case .jpeg:
            return "JPEG (smaller files)"
        }
    }

    static func current() -> ImagePasteFormat {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.imagePasteFormat) ?? ImagePasteFormat.png.rawValue
        return ImagePasteFormat(rawValue: raw) ?? .png
    }
}
