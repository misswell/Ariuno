import Foundation
import UIKit
import WebKit

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    var suggestedFilename: String
    var destinationURL: URL?
    var progress: Double
    var receivedBytes: Int64
    var totalBytes: Int64
    var state: State
    var errorText: String?
    var resumeData: Data?

    enum State: Equatable {
        case waiting
        case downloading
        case paused
        case finished
        case failed
        case cancelled
    }

    /// A finished download with a known on-disk location can be shared.
    var isShareable: Bool {
        state == .finished && destinationURL != nil
    }

    /// Resume is only offered when WebKit handed us resumable data.
    var isResumable: Bool {
        (state == .paused || state == .failed) && resumeData != nil
    }
}

/// Handles WKWebView downloads using WebKit's normal download API. Files are written into
/// the app's Documents/Downloads directory and can be paused (WebKit resume data), resumed,
/// shared and cancelled from the Downloads sheet. Progress is reported by WKDownload itself
/// (NSProgressReporting); no private APIs are involved.
@MainActor
final class DownloadManager: NSObject, ObservableObject {
    @Published private(set) var items: [DownloadItem] = []

    private var downloads: [ObjectIdentifier: (itemID: UUID, download: WKDownload)] = [:]
    private let downloadsDirectory: URL
    private var progressTimer: Timer?
    /// Offscreen WebView used only to resume paused/failed downloads; WebKit requires a
    /// WKWebView for resumeDownload(from:). Created lazily so tests never spin one up.
    private var resumeWebView: WKWebView?

    init(downloadsDirectory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.downloadsDirectory = (downloadsDirectory ?? documents.appendingPathComponent("Downloads", isDirectory: true))
        super.init()
        try? FileManager.default.createDirectory(at: self.downloadsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Registration

    func register(download: WKDownload, suggestedFilename: String? = nil) {
        let name = DownloadManager.sanitisedFilename(
            suggestedFilename ?? download.originalRequest?.url?.lastPathComponent ?? "download"
        )
        let item = DownloadItem(
            id: UUID(),
            suggestedFilename: name,
            destinationURL: nil,
            progress: 0,
            receivedBytes: 0,
            totalBytes: 0,
            state: .downloading,
            errorText: nil,
            resumeData: nil
        )
        items.insert(item, at: 0)
        attach(download: download, itemID: item.id)
    }

    func startDownload(url: URL, from webView: WKWebView) {
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            self?.register(download: download, suggestedFilename: url.lastPathComponent)
        }
    }

    /// Test/QA hook: inserts a tracked item without a backing WKDownload so that state
    /// transitions (pause/resume/cancel fallbacks) can be exercised in unit tests.
    @discardableResult
    func beginTrackedDownload(suggestedFilename: String, state: DownloadItem.State = .downloading) -> DownloadItem {
        let item = DownloadItem(
            id: UUID(),
            suggestedFilename: DownloadManager.sanitisedFilename(suggestedFilename),
            destinationURL: nil,
            progress: 0,
            receivedBytes: 0,
            totalBytes: 0,
            state: state,
            errorText: nil,
            resumeData: nil
        )
        items.insert(item, at: 0)
        return item
    }

    private func attach(download: WKDownload, itemID: UUID) {
        download.delegate = self
        downloads[ObjectIdentifier(download)] = (itemID, download)
        ensureProgressTimer()
    }

    // MARK: - User actions

    func pause(_ item: DownloadItem) {
        guard item.state == .waiting || item.state == .downloading else { return }
        guard let mapping = itemMapping(for: item) else {
            // No live WebKit download (e.g. injected item): still honour the pause request.
            update(itemID: item.id) {
                $0.state = .paused
            }
            return
        }
        update(itemID: item.id) {
            $0.state = .paused
        }
        mapping.download.cancel { [weak self] resumeData in
            guard let self else { return }
            Task { @MainActor in
                self.downloads.removeValue(forKey: ObjectIdentifier(mapping.download))
                self.update(itemID: item.id) {
                    $0.resumeData = resumeData
                    $0.state = .paused
                    if resumeData == nil && $0.errorText == nil {
                        $0.errorText = "此服务器不支持断点续传，暂停后无法继续"
                    }
                }
                self.refreshProgress()
            }
        }
    }

    func resume(_ item: DownloadItem) {
        guard item.isResumable, let resumeData = item.resumeData else { return }
        let webView = obtainResumeWebView()
        update(itemID: item.id) {
            $0.state = .downloading
            $0.errorText = nil
        }
        webView.resumeDownload(fromResumeData: resumeData) { [weak self] download in
            guard let self else { return }
            Task { @MainActor in
                // Keep the resume data until the download succeeds or fails again; a renewed
                // failure replaces it via download(_:didFail:resumeData:).
                self.attach(download: download, itemID: item.id)
            }
        }
    }

    func cancel(_ item: DownloadItem) {
        guard item.state != .finished else { return }
        if let mapping = itemMapping(for: item) {
            mapping.download.cancel { _ in }
            downloads.removeValue(forKey: ObjectIdentifier(mapping.download))
        }
        update(itemID: item.id) {
            $0.state = .cancelled
            $0.resumeData = nil
        }
        refreshProgress()
    }

    // MARK: - Internals

    private func itemMapping(for item: DownloadItem) -> (itemID: UUID, download: WKDownload)? {
        let objectID = downloads.first { _, mapping in mapping.itemID == item.id }?.key
        guard let objectID, let mapping = downloads[objectID] else { return nil }
        return mapping
    }

    private func update(itemID: UUID, transform: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        transform(&items[index])
    }

    private func obtainResumeWebView() -> WKWebView {
        if let resumeWebView { return resumeWebView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isHidden = true
        resumeWebView = webView
        return webView
    }

    private func ensureProgressTimer() {
        guard progressTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshProgress()
            }
        }
        progressTimer = timer
    }

    private func refreshProgress() {
        for (_, mapping) in downloads {
            let progress = mapping.download.progress
            let total = progress.totalUnitCount
            let received = Int64(max(0, progress.fractionCompleted))
            let fraction = total > 0 ? min(1.0, Double(received) / Double(total)) : 0
            update(itemID: mapping.itemID) { item in
                item.receivedBytes = received
                item.totalBytes = max(0, total)
                item.progress = fraction
            }
        }
        if downloads.isEmpty, let timer = progressTimer {
            timer.invalidate()
            progressTimer = nil
        }
    }

    /// Resolves a unique destination path inside the downloads directory. Internal so unit
    /// tests can assert the conflict-numbering behaviour.
    func resolveDestination(suggestedFilename: String) -> URL {
        let filename = DownloadManager.sanitisedFilename(suggestedFilename)
        var destination = downloadsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return destination
        }
        let ext = destination.pathExtension
        let base = ext.isEmpty ? destination.lastPathComponent : destination.deletingPathExtension().lastPathComponent
        var counter = 1
        repeat {
            destination = downloadsDirectory.appendingPathComponent(
                ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            )
            counter += 1
        } while FileManager.default.fileExists(atPath: destination.path)
        return destination
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
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        let suggested = suggestedFilename
            ?? response.suggestedFilename
            ?? download.originalRequest?.url?.lastPathComponent
            ?? "download"
        let destination = resolveDestination(suggestedFilename: suggested)
        if let mapping = downloads[ObjectIdentifier(download)] {
            update(itemID: mapping.itemID) {
                $0.destinationURL = destination
                let expected = Int64(response.expectedContentLength)
                if expected > 0 {
                    $0.totalBytes = expected
                }
            }
        }
        completionHandler(destination)
    }

    nonisolated func download(_ download: WKDownload, didReceiveFinalURL url: URL) {
        Task { @MainActor in
            if let mapping = self.downloads[ObjectIdentifier(download)] {
                self.update(itemID: mapping.itemID) {
                    $0.destinationURL = url
                }
            }
        }
    }

    func download(_ download: WKDownload, didReceivePlaceholderURL url: URL, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let mapping = downloads[ObjectIdentifier(download)] else { return }
        downloads.removeValue(forKey: ObjectIdentifier(download))
        update(itemID: mapping.itemID) {
            $0.progress = 1
            $0.state = .finished
            $0.errorText = nil
        }
    }

    func download(_ download: WKDownload, didFail error: Error, resumeData: Data?) {
        guard let mapping = downloads[ObjectIdentifier(download)] else { return }
        downloads.removeValue(forKey: ObjectIdentifier(download))
        update(itemID: mapping.itemID) {
            $0.state = .failed
            $0.errorText = PrivacyRedactor.redact(error.localizedDescription)
            $0.resumeData = resumeData
        }
    }
}
