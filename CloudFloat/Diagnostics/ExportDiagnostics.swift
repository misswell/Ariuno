import Foundation
import UIKit
import SwiftUI

struct DiagnosticsEnvironment: Codable, Equatable {
    let appVersion: String
    let appBuild: String
    let osVersion: String
    let deviceModel: String
    let localeIdentifier: String
    let isSimulator: Bool
    let exportedAt: Date
}

struct DiagnosticsExportPayload: Codable {
    let environment: DiagnosticsEnvironment
    let session: SessionDiagnosticsSnapshot?
    let privacyNotice: String
    let events: [DiagnosticEvent]
}

enum DiagnosticsExportFormat: String, CaseIterable, Identifiable {
    case json
    case text

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .text: return "纯文本"
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "txt"
        }
    }
}

@MainActor
enum ExportDiagnostics {
    static func environment(now: Date = Date()) -> DiagnosticsEnvironment {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        return DiagnosticsEnvironment(
            appVersion: version,
            appBuild: build,
            osVersion: UIDevice.current.systemVersion,
            deviceModel: hardwareIdentifier(),
            localeIdentifier: Locale.current.identifier,
            isSimulator: isSimulator,
            exportedAt: now
        )
    }

    static func jsonData(events: [DiagnosticEvent], session: SessionDiagnosticsSnapshot?) throws -> Data {
        let payload = DiagnosticsExportPayload(
            environment: environment(),
            session: session,
            privacyNotice: FeatureFlags.privacyStatement,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func textReport(events: [DiagnosticEvent], session: SessionDiagnosticsSnapshot?) -> String {
        let env = environment()
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("CloudFloat Diagnostics")
        lines.append("=====================")
        lines.append("App: \(env.appVersion) (\(env.appBuild))")
        lines.append("OS: \(env.osVersion) [\(env.deviceModel)]\(env.isSimulator ? " (Simulator)" : "")")
        lines.append("Locale: \(env.localeIdentifier)")
        lines.append("Exported: \(formatter.string(from: env.exportedAt))")
        lines.append("Privacy: \(FeatureFlags.privacyStatement)")
        lines.append("")
        if let session {
            lines.append("Session")
            lines.append("-------")
            lines.append("State: \(session.state.rawValue)")
            lines.append("PiP visible: \(session.pipVisible)")
            lines.append("Media playing observed: \(session.mediaPlayingObserved)")
            lines.append("Server session verified: \(session.serverSessionVerified)")
            lines.append("Network: \(session.networkStatus)")
            lines.append("Recovery attempts: \(session.recoveryAttempts)")
            lines.append("Failure: \(session.failureReason ?? "-")")
            if let date = session.lastPlayingObservedAt {
                lines.append("Last playing observed: \(formatter.string(from: date))")
            }
            if let date = session.lastMediaActivityAt {
                lines.append("Last media activity: \(formatter.string(from: date))")
            }
            if let date = session.lastBackgroundAt {
                lines.append("Last background: \(formatter.string(from: date))")
            }
            if let date = session.lastForegroundAt {
                lines.append("Last foreground: \(formatter.string(from: date))")
            }
            lines.append("")
        }
        lines.append("Events (\(events.count))")
        lines.append("-----------------")
        for event in events {
            let timestamp = formatter.string(from: event.timestamp)
            lines.append("[\(timestamp)] [\(event.severity.rawValue.uppercased())] [\(event.category.rawValue)] \(event.code): \(event.message)")
            if !event.metadata.isEmpty {
                let metadata = event.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                lines.append("    {\(metadata)}")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func writeTemporaryFile(
        events: [DiagnosticEvent],
        session: SessionDiagnosticsSnapshot?,
        format: DiagnosticsExportFormat
    ) throws -> URL {
        let data: Data
        switch format {
        case .json:
            data = try jsonData(events: events, session: session)
        case .text:
            data = Data(textReport(events: events, session: session).utf8)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = UUID().uuidString.prefix(6)
        let filename = "CloudFloat-Diagnostics-\(formatter.string(from: Date()))-\(suffix).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: url.path
        )
        return url
    }

    static func removeTemporaryExport(at url: URL) {
        guard url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
