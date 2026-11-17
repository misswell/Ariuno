import XCTest
@testable import Ariuno

@MainActor
final class DownloadManagerTests: XCTestCase {
    private var directory: URL!
    private var manager: DownloadManager!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoDownloads-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager = DownloadManager(downloadsDirectory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        manager = nil
        directory = nil
        super.tearDown()
    }

    // MARK: - Filename handling

    func testSanitisedFilenameStripsUnsafeCharactersAndEmpties() {
        XCTAssertEqual(DownloadManager.sanitisedFilename("a/b:c.zip"), "a-b-c.zip")
        XCTAssertEqual(DownloadManager.sanitisedFilename("   "), "download")
        XCTAssertEqual(DownloadManager.sanitisedFilename("示例 文件.zip"), "示例 文件.zip")
        XCTAssertEqual(
            DownloadManager.sanitisedFilename(String(repeating: "x", count: 300)).count,
            180
        )
    }

    func testResolveDestinationReturnsOriginalNameWhenFree() {
        let destination = manager.resolveDestination(suggestedFilename: "file.zip")
        XCTAssertEqual(destination.lastPathComponent, "file.zip")
        XCTAssertEqual(destination.deletingLastPathComponent(), directory)
    }

    func testResolveDestinationNumbersConflictingFiles() {
        FileManager.default.createFile(atPath: directory.appendingPathComponent("file.zip").path, contents: Data())
        FileManager.default.createFile(atPath: directory.appendingPathComponent("file-1.zip").path, contents: Data())

        let destination = manager.resolveDestination(suggestedFilename: "file.zip")
        XCTAssertEqual(destination.lastPathComponent, "file-2.zip")
    }

    func testResolveDestinationWithoutExtensionNumbersConflicts() {
        FileManager.default.createFile(atPath: directory.appendingPathComponent("readme").path, contents: Data())

        let destination = manager.resolveDestination(suggestedFilename: "readme")
        XCTAssertEqual(destination.lastPathComponent, "readme-1")
    }

    // MARK: - Item states

    func testBeginTrackedDownloadExposesItem() {
        let item = manager.beginTrackedDownload(suggestedFilename: "video.mp4")
        XCTAssertEqual(manager.items.first?.id, item.id)
        XCTAssertEqual(item.state, .downloading)
        XCTAssertEqual(item.suggestedFilename, "video.mp4")
        XCTAssertEqual(item.progress, 0)
    }

    func testPauseWithoutLiveDownloadMarksPausedWithoutResumeData() {
        let item = manager.beginTrackedDownload(suggestedFilename: "a.zip")
        manager.pause(item)
        XCTAssertEqual(manager.items.first?.state, .paused)
        XCTAssertNil(manager.items.first?.resumeData)
        XCTAssertFalse(manager.items.first!.isResumable)
    }

    func testPauseFinishedItemIsNoOp() {
        let item = manager.beginTrackedDownload(suggestedFilename: "a.zip", state: .finished)
        manager.pause(item)
        XCTAssertEqual(manager.items.first?.state, .finished)
    }

    func testResumeWithoutResumeDataIsNoOp() {
        let item = manager.beginTrackedDownload(suggestedFilename: "a.zip", state: .paused)
        manager.resume(item)
        XCTAssertEqual(manager.items.first?.state, .paused)
    }

    func testCancelWithoutLiveDownloadMarksCancelledAndClearsResumeData() {
        let item = manager.beginTrackedDownload(suggestedFilename: "a.zip", state: .failed)
        manager.cancel(item)
        XCTAssertEqual(manager.items.first?.state, .cancelled)
        XCTAssertNil(manager.items.first?.resumeData)
    }

    func testCancelFinishedItemIsNoOp() {
        let item = manager.beginTrackedDownload(suggestedFilename: "a.zip", state: .finished)
        manager.cancel(item)
        XCTAssertEqual(manager.items.first?.state, .finished)
    }

    func testShareableRequiresFinishedStateAndDestination() {
        let downloading = manager.beginTrackedDownload(suggestedFilename: "a.zip")
        XCTAssertFalse(downloading.isShareable)

        let paused = manager.beginTrackedDownload(suggestedFilename: "b.zip", state: .paused)
        XCTAssertFalse(paused.isShareable)

        let finished = manager.beginTrackedDownload(suggestedFilename: "c.zip", state: .finished)
        XCTAssertFalse(finished.isShareable, "无落盘地址时不可分享")
    }

    func testResumableRequiresResumeData() {
        let pausedWithoutData = manager.beginTrackedDownload(suggestedFilename: "a.zip", state: .paused)
        XCTAssertFalse(pausedWithoutData.isResumable)
    }

    func testItemsArePrependedNewestFirst() {
        let first = manager.beginTrackedDownload(suggestedFilename: "1.zip")
        let second = manager.beginTrackedDownload(suggestedFilename: "2.zip")
        XCTAssertEqual(manager.items.map(\.id), [second.id, first.id])
    }
}
