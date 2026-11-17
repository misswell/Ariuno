import UIKit
import WebKit

/// Tab thumbnails come from `WKWebView.takeSnapshot`, are written as PNG files under the
/// app's Caches directory, and are removed when the tab closes. UserDefaults is never used
/// for images, and the OS may purge Caches under memory pressure — both are intentional.
@MainActor
final class TabThumbnailCache {
    static let shared = TabThumbnailCache()

    private let directory: URL
    private let maxAge: TimeInterval
    private let fileManager: FileManager

    init(directory: URL? = nil, maxAge: TimeInterval = 120, fileManager: FileManager = .default) {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directory = directory ?? caches
            .appendingPathComponent("Ariuno", isDirectory: true)
            .appendingPathComponent("TabThumbnails", isDirectory: true)
        self.maxAge = maxAge
        self.fileManager = fileManager
        try? self.fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    var storageDirectory: URL { directory }

    func fileURL(for tabID: UUID) -> URL {
        directory.appendingPathComponent("\(tabID.uuidString).png")
    }

    func cachedImage(for tabID: UUID, now: Date = Date()) -> UIImage? {
        let url = fileURL(for: tabID)
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(modified) <= maxAge,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// Returns a cached thumbnail when fresh, otherwise takes a new snapshot and persists it.
    func image(
        for tabID: UUID,
        webView: WKWebView,
        forceRefresh: Bool = false
    ) async -> UIImage? {
        if !forceRefresh, let cached = cachedImage(for: tabID) {
            return cached
        }
        guard let image = await snapshot(of: webView) else { return cachedImage(for: tabID) }
        persist(image, tabID: tabID)
        return image
    }

    func persist(_ image: UIImage, tabID: UUID) {
        guard let data = image.pngData() else { return }
        let url = fileURL(for: tabID)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    func remove(tabID: UUID) {
        try? fileManager.removeItem(at: fileURL(for: tabID))
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func snapshot(of webView: WKWebView) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = false
            webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
