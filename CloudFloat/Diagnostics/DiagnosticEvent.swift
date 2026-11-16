import Foundation

/// Category groups used by the in-app diagnostics log.
enum DiagnosticCategory: String, Codable, CaseIterable, Identifiable {
    case app
    case navigation
    case media
    case pip
    case session
    case network
    case recovery
    case security
    case privacy
    case test

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .app: return "App"
        case .navigation: return "导航"
        case .media: return "媒体"
        case .pip: return "画中画"
        case .session: return "会话"
        case .network: return "网络"
        case .recovery: return "恢复"
        case .security: return "安全"
        case .privacy: return "隐私"
        case .test: return "测试"
        }
    }
}

enum DiagnosticSeverity: String, Codable, CaseIterable, Comparable {
    case debug
    case info
    case warning
    case error

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: DiagnosticSeverity, rhs: DiagnosticSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }
}

/// One redacted diagnostics record. Construction through `DiagnosticsStore` applies
/// `PrivacyRedactor`; do not put credentials or tokenized URLs in `code` either.
struct DiagnosticEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let category: DiagnosticCategory
    let severity: DiagnosticSeverity
    let code: String
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: DiagnosticCategory,
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.severity = severity
        self.code = code
        self.message = message
        self.metadata = metadata
    }
}
