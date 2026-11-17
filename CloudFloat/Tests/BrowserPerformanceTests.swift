import XCTest
@testable import Ariuno

/// Simulator-only performance probes. Values are printed with the `PERF` prefix so the
/// acceptance report can quote real measurements instead of estimates. Real-device numbers
/// must be collected separately (see docs/acceptance-report.md).
@MainActor
final class BrowserPerformanceTests: XCTestCase {
    private var managers: [BrowserTabManager] = []

    override func tearDown() {
        managers.forEach { $0.shutdown() }
        managers = []
        super.tearDown()
    }

    func testTabCreationAndSwitchingCost() {
        let manager = BrowserTabManager()
        managers.append(manager)
        _ = footprintMB()

        let createStart = CFAbsoluteTimeGetCurrent()
        var sessions = [manager.activeSession]
        for _ in 0..<9 {
            sessions.append(manager.createTab(activate: false))
        }
        let createMs = (CFAbsoluteTimeGetCurrent() - createStart) * 1000

        let switchStart = CFAbsoluteTimeGetCurrent()
        for index in 0..<200 {
            manager.activateTab(sessions[index % sessions.count])
        }
        let switchMs = (CFAbsoluteTimeGetCurrent() - switchStart) * 1000

        let footprint = footprintMB()
        print(String(
            format: "PERF tabs.create10=%.1fms tabs.switch200=%.1fms tabs.switchAvg=%.2fms footprint.10tabs=%.1fMB",
            createMs,
            switchMs,
            switchMs / 200.0,
            footprint
        ))

        XCTAssertEqual(manager.sessions.count, 10)
        XCTAssertLessThan(createMs / 10.0, 200.0, "单个标签创建不应出现数量级异常")
        XCTAssertLessThan(switchMs / 200.0, 50.0, "标签切换应远低于一帧级开销")
    }

    func testClosingTenTabsReleasesThem() {
        let manager = BrowserTabManager()
        managers.append(manager)
        var sessions = [manager.activeSession]
        for _ in 0..<9 {
            sessions.append(manager.createTab(activate: false))
        }
        let before = footprintMB()

        let closeStart = CFAbsoluteTimeGetCurrent()
        manager.closeTabs(withIDs: sessions.map(\.id), force: true)
        let closeMs = (CFAbsoluteTimeGetCurrent() - closeStart) * 1000
        let after = footprintMB()

        print(String(
            format: "PERF tabs.close10=%.1fms footprint.beforeClose=%.1fMB footprint.afterClose=%.1fMB",
            closeMs,
            before,
            after
        ))
        XCTAssertEqual(manager.sessions.count, 1, "全部关闭后保留一个空白标签")
    }

    func testHistoryAndBookmarkWritesStayFast() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AriunoPerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = HistoryStore(fileURL: directory.appendingPathComponent("history.json"))

        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<1_000 {
            history.record(
                title: "page \(index)",
                url: URL(string: "https://example.com/\(index)")!,
                visitedAt: Date().addingTimeInterval(TimeInterval(index))
            )
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "PERF history.record1000=%.1fms", elapsed))
        XCTAssertEqual(history.entries.count, 1_000)
        XCTAssertLessThan(elapsed, 2_000, "1000 条历史写入应保持在秒级以内")
    }

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576.0
    }
}
