import Foundation

/// Bounded, redacted, in-memory diagnostics log.
///
/// The store is deliberately memory-only: diagnostics are exported when the user asks and
/// are not written to disk automatically, which keeps accidental credential persistence out
/// of the app. Events are capped and the oldest entries are dropped.
@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var events: [DiagnosticEvent] = []
    @Published private(set) var droppedEventCount: Int = 0

    let capacity: Int
    private let now: () -> Date

    init(capacity: Int = FeatureFlags.diagnosticsCapacity, now: @escaping () -> Date = Date.init) {
        self.capacity = max(50, capacity)
        self.now = now
    }

    func record(
        category: DiagnosticCategory,
        severity: DiagnosticSeverity = .info,
        code: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        let event = DiagnosticEvent(
            timestamp: now(),
            category: category,
            severity: severity,
            code: String(code.prefix(80)),
            message: PrivacyRedactor.redact(String(message.prefix(2_000))),
            metadata: PrivacyRedactor.redact(metadata: metadata)
        )
        append(event)
    }

    func debug(
        _ category: DiagnosticCategory,
        _ code: String,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        record(category: category, severity: .debug, code: code, message: message, metadata: metadata)
    }

    func info(
        _ category: DiagnosticCategory,
        _ code: String,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        record(category: category, severity: .info, code: code, message: message, metadata: metadata)
    }

    func warning(
        _ category: DiagnosticCategory,
        _ code: String,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        record(category: category, severity: .warning, code: code, message: message, metadata: metadata)
    }

    func error(
        _ category: DiagnosticCategory,
        _ code: String,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        record(category: category, severity: .error, code: code, message: message, metadata: metadata)
    }

    func clear() {
        events.removeAll()
        droppedEventCount = 0
    }

    var highestSeverity: DiagnosticSeverity? {
        events.map(\.severity).max()
    }

    private func append(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > capacity {
            let overflow = events.count - capacity
            events.removeFirst(overflow)
            droppedEventCount += overflow
        }
    }
}
