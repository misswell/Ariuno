import Foundation
import UIKit
import WebKit

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var suggestedFilename: String
    var destinationURL: URL?
    var progress: Double
    var state: State
    var errorText: String?

    enum State: Equatable {
        case waiting
        case downloading
        case finished
        case failed
        case cancelled
    }
}

/// Handles WKWebView downloads using WebKit's normal download API. Files are written into
/// the app's Documents/Downloads directory and can be shared from the Downloads sheet.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private var downloads: [ObjectIdentifier: (itemID: UUID, download: WKDownload)] = [:]
    private var itemByUUID: [UUID: UUID] = [:]
    private let downloadsDirectory: URL

    init(downloadsDirectory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.downloadsDirectory = (downloadsDirectory ?? documents.appendingPathComponent("Downloads", isDirectory: true))
        super.init()
        try? FileManager.default.createDirectory(at: self.downloadsDirectory, withIntermediateDirectories: true)
    }

    func register(download: WKDownload, suggestedFilename: String? = nil) {
        let itemID = UUID()
        let name = DownloadManager.sanitisedFilename(suggestedFilename ?? download.originalRequest?.url?.lastPathComponent ?? "download")
        let item = DownloadItem(
            id: itemID,
            suggestedFilename: name,
            destinationURL: nil,
            progress: 0,
            state: .downloading,
            errorText: nil
        )
        items.insert(item, at: 0)
        downloads[ObjectIdentifier(download)] = (itemID, download)
        itemByUUID[itemID] = UUID()
        download.delegate = self
    }

    func startDownload(url: URL, from webView: WKWebView) {
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            self?.register(download: download, suggestedFilename: url.lastPathComponent)
        }
    }

    func cancel(_ item: DownloadItem) {
        guard let mapping = itemMapping(for: item) else { return }
        mapping.download.cancel { _ in }
        update(itemID: item.id) {
            $0.state = .cancelled
        }
    }

    private func itemMapping(for item: DownloadItem) -> (itemID: UUID, download: WKDownload)? {
        let objectID = downloads.first { _, mapping in mapping.itemID == item.id }?.key
        guard let objectID, let mapping = downloads[objectID] else { return nil }
        return mapping
    }

    private func update(itemID: UUID, transform: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        transform(&items[index])
    }

    nonisolated static func sanitisedFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safe.isEmpty ? "download" : String(safe.prefix(180))
    }
}

extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String?,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let suggested = suggestedFilename ?? response.suggestedFilename ?? download.originalRequest?.url?.lastPathComponent ?? "download"
        let filename = DownloadManager.sanitisedFilename(suggested)
        var destination = downloadsDirectory.appendingPathComponent(filename)
        var counter = 1
        let base = destination.deletingPathExtension()
        let ext = destination.pathExtension
        while FileManager.default.fileExists(atPath: destination.path) {
            let name = ext.isEmpty ? base.lastPathComponent : base.lastPathComponent
            destination = downloadsDirectory.appendingPathComponent("\(name)-\(counter)\(ext.isEmpty ? "" : ".\(ext)")")
            counter += 1
        }
        completionHandler(destination)
    }

    nonisolated func download(_ download: WKDownload, didReceiveFinalURL url: URL) {}

    func download(_ download: WKDownload, didReceivePlaceholderURL url: URL, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let mapping = downloads[ObjectIdentifier(download)] else { return }
        // The final URL is available on newer OS versions; otherwise keep the destination unset.
        update(itemID: mapping.itemID) {
            $0.progress = 1
            $0.state = .finished
        }
    }

    func download(_ download: WKDownload, didFail error: Error, resumeData: Data?) {
        guard let mapping = downloads[ObjectIdentifier(download)] else { return }
        update(itemID: mapping.itemID) {
            $0.state = .failed
            $0.errorText = PrivacyRedactor.redact(error.localizedDescription)
        }
    }
}

