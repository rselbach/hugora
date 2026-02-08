import Foundation

// MARK: - Image Context

/// Context for resolving image paths relative to Hugo's site structure.
struct ImageContext {
    let postURL: URL           // URL of the current .md file
    let siteURL: URL           // URL of the Hugo site root
    let remoteImagesEnabled: Bool

    init(postURL: URL, siteURL: URL, remoteImagesEnabled: Bool = false) {
        self.postURL = postURL
        self.siteURL = siteURL
        self.remoteImagesEnabled = remoteImagesEnabled
    }

    /// Resolves an image path according to Hugo conventions:
    /// - `/some-path/my-image.png` -> static/some-path/my-image.png
    /// - `assets/my-image.png` -> assets/my-image.png
    /// - `my-image.png` -> same directory as the post
    func resolveImagePath(_ source: String) -> URL? {
        guard !source.isEmpty else { return nil }

        // Handle remote URLs
        if source.hasPrefix("http://") || source.hasPrefix("https://") {
            return remoteImagesEnabled ? URL(string: source) : nil
        }

        if source.hasPrefix("/") {
            // Absolute path from site root -> static/
            let relativePath = String(source.dropFirst())
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("static").appendingPathComponent(relativePath)
            )
        }

        if source.hasPrefix("assets/") {
            let relativePath = String(source.dropFirst("assets/".count))
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("assets").appendingPathComponent(relativePath)
            )
        }

        if source.hasPrefix("static/") {
            let relativePath = String(source.dropFirst("static/".count))
            return sanitizedLocalURL(
                siteURL.appendingPathComponent("static").appendingPathComponent(relativePath)
            )
        }

        // Relative path from post's directory
        let postDirectory = postURL.deletingLastPathComponent()
        return sanitizedLocalURL(postDirectory.appendingPathComponent(source))
    }

    private func sanitizedLocalURL(_ url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        let sitePath = siteURL.standardizedFileURL.path
        let postPath = postURL.deletingLastPathComponent().standardizedFileURL.path
        let candidatePath = standardized.path

        guard candidatePath.hasPrefix(sitePath) || candidatePath.hasPrefix(postPath) else {
            return nil
        }

        return standardized
    }
}
