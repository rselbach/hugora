import AppKit
import Foundation

// MARK: - Image Cache

/// Simple in-memory cache for loaded images.
final class ImageCache {
    static let shared = ImageCache()

    private struct Entry {
        let image: NSImage
        let cost: Int
    }

    private var cache: [URL: Entry] = [:]
    private var order: [URL] = []
    private var totalCost: Int = 0
    private let countLimit: Int
    private let totalCostLimit: Int
    private let queue = DispatchQueue(label: "com.hugora.imagecache", attributes: .concurrent)

    init(countLimit: Int = 128, totalCostLimit: Int = 128 * 1024 * 1024) {
        self.countLimit = max(countLimit, 1)
        self.totalCostLimit = max(totalCostLimit, 1)
    }

    func image(for url: URL) -> NSImage? {
        queue.sync {
            guard let entry = cache[url] else { return nil }
            markAsRecentlyUsed(url)
            return entry.image
        }
    }

    func setImage(_ image: NSImage, for url: URL) {
        let cost = imageCost(image)
        queue.sync(flags: .barrier) {
            if let existing = cache[url] {
                totalCost -= existing.cost
                removeFromOrder(url)
            }

            cache[url] = Entry(image: image, cost: cost)
            order.append(url)
            totalCost += cost
            enforceLimits()
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            cache.removeAll()
            order.removeAll()
            totalCost = 0
        }
    }

    private func markAsRecentlyUsed(_ url: URL) {
        guard let index = order.firstIndex(of: url) else { return }
        order.remove(at: index)
        order.append(url)
    }

    private func removeFromOrder(_ url: URL) {
        if let index = order.firstIndex(of: url) {
            order.remove(at: index)
        }
    }

    private func enforceLimits() {
        while cache.count > countLimit || totalCost > totalCostLimit {
            guard let oldest = order.first,
                  let entry = cache[oldest] else {
                break
            }
            cache.removeValue(forKey: oldest)
            order.removeFirst()
            totalCost -= entry.cost
        }
    }

    private func imageCost(_ image: NSImage) -> Int {
        let reps = image.representations
        let maxPixels = reps.map { $0.pixelsWide * $0.pixelsHigh }.max() ?? 0
        let fallbackPixels = Int(image.size.width * image.size.height)
        let pixels = max(maxPixels, fallbackPixels)
        return max(pixels * 4, 1)
    }
}
