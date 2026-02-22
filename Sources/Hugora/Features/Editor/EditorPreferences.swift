import Foundation

struct EditorPreferences {
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    static func current() -> EditorPreferences {
        let defaults = UserDefaults.standard
        let storedFontSize = defaults.object(forKey: DefaultsKey.editorFontSize) as? Double ?? 16
        let storedLineSpacing = defaults.object(forKey: DefaultsKey.editorLineSpacing) as? Double ?? 1.4
        return EditorPreferences(
            fontSize: CGFloat(max(storedFontSize, 1)),
            lineSpacing: CGFloat(max(storedLineSpacing, 1))
        )
    }

    func fontScale(for theme: Theme) -> CGFloat {
        let baseSize = max(theme.baseFont.pointSize, 1)
        return fontSize / baseSize
    }
}
