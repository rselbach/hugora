import Foundation

struct ImagePasteDestination: Equatable {
    let saveURL: URL
    let markdownPath: String
}

enum ImagePasteDestinationAllocator {
    static func destination(
        context: ImageContext,
        location: ImagePasteLocation,
        filename: String,
        fileManager: FileManager = .default
    ) -> ImagePasteDestination {
        var candidate = filename
        var destination = rawDestination(context: context, location: location, filename: candidate)
        var counter = 1

        while fileManager.fileExists(atPath: destination.saveURL.path) {
            candidate = appendCounter(counter, to: filename)
            destination = rawDestination(context: context, location: location, filename: candidate)
            counter += 1
        }

        return destination
    }

    static func rawDestination(
        context: ImageContext,
        location: ImagePasteLocation,
        filename: String
    ) -> ImagePasteDestination {
        switch location {
        case .pageFolder:
            let postDirectory = context.postURL.deletingLastPathComponent()
            return ImagePasteDestination(saveURL: postDirectory.appendingPathComponent(filename), markdownPath: filename)
        case .siteStatic:
            let staticDirectory = context.siteURL.appendingPathComponent("static")
            return ImagePasteDestination(saveURL: staticDirectory.appendingPathComponent(filename), markdownPath: "/\(filename)")
        case .siteAssets:
            let assetsDirectory = context.siteURL.appendingPathComponent("assets")
            return ImagePasteDestination(saveURL: assetsDirectory.appendingPathComponent(filename), markdownPath: "assets/\(filename)")
        }
    }

    private static func appendCounter(_ counter: Int, to filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        let basename = url.deletingPathExtension().lastPathComponent

        guard !ext.isEmpty else {
            return "\(basename)-\(counter)"
        }

        return "\(basename)-\(counter).\(ext)"
    }
}
