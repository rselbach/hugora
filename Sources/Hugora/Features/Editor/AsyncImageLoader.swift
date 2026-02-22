import AppKit
import Foundation

extension Notification.Name {
    static let asyncImageLoaderDidLoad = Notification.Name("com.hugora.asyncImageLoaderDidLoad")
}

final class AsyncImageLoader {
    static let shared = AsyncImageLoader()

    private var inFlight: Set<URL> = []
    private let queue = DispatchQueue(label: "com.hugora.asyncImageLoader", qos: .utility)

    func load(_ url: URL) {
        queue.async { [weak self] in
            guard let self else { return }
            guard !self.inFlight.contains(url) else { return }
            self.inFlight.insert(url)
            defer { self.inFlight.remove(url) }

            guard FileManager.default.fileExists(atPath: url.path),
                  let image = NSImage(contentsOf: url) else {
                return
            }

            ImageCache.shared.setImage(image, for: url)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .asyncImageLoaderDidLoad, object: url)
            }
        }
    }
}
