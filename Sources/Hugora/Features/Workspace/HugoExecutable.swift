import Foundation

/// Locates the hugo binary for everything that shells out to it (post
/// creation, the preview server).
enum HugoExecutable {
    static let standardLocations = [
        "/opt/homebrew/bin/hugo",
        "/usr/local/bin/hugo",
        "/usr/bin/hugo",
    ]

    /// Resolution order: the in-app setting, then HUGORA_HUGO_PATH (only
    /// reaches the app when launched from a shell — Finder-launched apps
    /// don't inherit shell environment), then standard install locations.
    static func resolve(fileManager: FileManager = .default) -> URL? {
        if let configured = UserDefaults.standard.string(forKey: DefaultsKey.hugoExecutablePath),
            !configured.isEmpty
        {
            if let url = executableURL(at: configured, fileManager: fileManager) {
                return url
            }
        }

        if let fromEnv = ProcessInfo.processInfo.environment["HUGORA_HUGO_PATH"],
            !fromEnv.isEmpty,
            let url = executableURL(at: fromEnv, fileManager: fileManager)
        {
            return url
        }

        for path in standardLocations where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }

    private static func executableURL(at path: String, fileManager: FileManager) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard fileManager.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }
}
