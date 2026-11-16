import XCTest
@testable import CloudFloat

@MainActor
final class DiagnosticsStoreTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(capacity: Int = 50) -> DiagnosticsStore {
        DiagnosticsStore(capacity: capacity, now: { [weak self] in self?.clock ?? Date() })
    }

    func testCapacityDropsOldestEvents() {
        let store = makeStore(capacity: 50)
        for index in 0..<55 {
            store.info(.app, "test.\(index)", "event \(index)")
        }
        XCTAssertEqual(store.events.count, 50)
        XCTAssertEqual(store.droppedEventCount, 5)
        XCTAssertEqual(store.events.first?.code, "test.5")
        XCTAssertEqual(store.events.last?.code, "test.54")
    }

    func testRedactionIsAppliedOnWrite() {
        let store = makeStore()
        store.record(
            category: .navigation,
            severity: .error,
            code: "nav.failure",
            message: "failed https://sr.mihoyo.com/cloud/?token=abc with Cookie: ltoken=secret",
            metadata: ["host": "sr.mihoyo.com", "cookie": "ltoken=secret", "token": "abc"]
        )
        let event = store.events.first
        XCTAssertNotNil(event)
        XCTAssertFalse(event?.message.contains("abc") ?? true)
        XCTAssertFalse(event?.message.contains("secret") ?? true)
        XCTAssertEqual(event?.metadata["cookie"], "<redacted>")
        XCTAssertEqual(event?.metadata["token"], "<redacted>")
        XCTAssertEqual(event?.metadata["host"], "sr.mihoyo.com")
    }

    func testClearRemovesEventsAndDropCount() {
        let store = makeStore()
        store.info(.app, "a", "one")
        store.warning(.media, "b", "two")
        XCTAssertEqual(store.highestSeverity, .warning)
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.droppedEventCount, 0)
        XCTAssertNil(store.highestSeverity)
    }

    func testConvenienceSeverityLevels() {
        let store = makeStore()
        store.debug(.app, "d", "debug")
        store.info(.app, "i", "info")
        store.warning(.app, "w", "warning")
        store.error(.app, "e", "error")
        XCTAssertEqual(store.events.map(\.severity), [.debug, .info, .warning, .error])
        XCTAssertEqual(store.highestSeverity, .error)
    }

    func testTimestampsUseInjectedClock() {
        let store = makeStore()
        store.info(.app, "a", "one")
        XCTAssertEqual(store.events.first?.timestamp, clock)
    }

    func testJSONExportRoundTripsAndContainsPrivacyNotice() throws {
        let store = makeStore()
        store.info(.app, "app.launch", "CloudFloat 启动")
        let data = try ExportDiagnostics.jsonData(events: store.events, session: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DiagnosticsExportPayload.self, from: data)
        XCTAssertEqual(payload.events.count, 1)
        XCTAssertTrue(payload.privacyNotice.contains("CloudFloat"))
        XCTAssertFalse(payload.environment.osVersion.isEmpty)
        XCTAssertEqual(payload.environment.isSimulator, true)
    }

    func testTextExportContainsSessionAndEvents() {
        let store = makeStore()
        store.warning(.media, "media.stalled", "video stalled")
        let report = ExportDiagnostics.textReport(
            events: store.events,
            session: SessionDiagnosticsSnapshot(
                state: .streamStalled,
                failureReason: "no progress",
                lastPiPFailureReason: nil,
                pipVisible: false,
                mediaPlayingObserved: false,
                lastMediaActivityAt: clock,
                lastPlayingObservedAt: nil,
                lastForegroundAt: nil,
                lastBackgroundAt: nil,
                appIsForeground: true,
                networkStatus: "wifi",
                recoveryAttempts: 0,
                serverSessionVerified: false,
                mediaProbePolling: true,
                recordedAt: clock
            )
        )
        XCTAssertTrue(report.contains("CloudFloat Diagnostics"))
        XCTAssertTrue(report.contains("streamStalled"))
        XCTAssertTrue(report.contains("Server session verified: false"))
        XCTAssertTrue(report.contains("media.stalled"))
        XCTAssertTrue(report.contains("UNVERIFIED") || report.contains("privacy"))
    }

    func testTemporaryExportFileIsWrittenAndRemoved() throws {
        let store = makeStore()
        store.info(.app, "a", "one")
        let url = try ExportDiagnostics.writeTemporaryFile(
            events: store.events,
            session: nil,
            format: .json
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        ExportDiagnostics.removeTemporaryExport(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
