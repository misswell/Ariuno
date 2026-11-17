import Foundation

enum NavigationContext: String, Equatable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case other
}

enum NavigationBlockReason: String, Equatable {
    case noURL
    case fileOutsideAllowedScope
    case unsafeScheme
    case untrustedCustomScheme
    case appInstallScheme
    case localTestPagesDisabled
}

enum NavigationDecision: Equatable {
    case allow
    case openExternally(URL)
    case block(NavigationBlockReason)
}

/// Ariuno is a general browser: all ordinary http/https navigations stay in-app. Only unsafe
/// schemes and app-install/data URLs are blocked. External system schemes still require the
/// existing user confirmation flow.
struct NavigationPolicy: Equatable {
    var allowsLocalTestPages: Bool = false
    var localTestHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
    var localTestPorts: Set<Int> = []
    var allowedFileDirectory: URL?

    var isEmptyAllowList: Bool { true }

    func isLocalTestURL(_ url: URL) -> Bool {
        guard allowsLocalTestPages else { return false }
        guard url.scheme?.lowercased() == "http" else { return false }
        guard let host = NavigationPolicy.normalisedHost(url.host), localTestHosts.contains(host) else { return false }
        if localTestPorts.isEmpty {
            return true
        }
        guard let port = url.port else { return false }
        return localTestPorts.contains(port)
    }

    func decision(
        for url: URL?,
        context: NavigationContext,
        isMainFrame: Bool
    ) -> NavigationDecision {
        guard let url else {
            // WebKit uses nil/empty requests for about:blank popups/new windows internally.
            return .allow
        }
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "about":
            return .allow

        case "https", "http":
            // Ariuno is a browser: both secure and ordinary HTTP pages stay in-app. The UI
            // labels HTTP as not secure; ATS still applies to app-level networking.
            return .allow

        case "file":
            guard allowsLocalTestPages else {
                return .block(.localTestPagesDisabled)
            }
            guard let directory = allowedFileDirectory?.standardizedFileURL else {
                return .block(.fileOutsideAllowedScope)
            }
            let target = url.standardizedFileURL
            let dirPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            guard target.path.hasPrefix(dirPath) else {
                return .block(.fileOutsideAllowedScope)
            }
            return .allow

        case "mailto", "tel", "sms", "facetime", "facetime-audio":
            if isMainFrame {
                return .openExternally(url)
            }
            return .block(.unsafeScheme)

        case "itms-services", "itms-apps", "itms-appss":
            return .block(.appInstallScheme)

        case "javascript", "data", "filesystem":
            return .block(.unsafeScheme)

        case "":
            return .block(.noURL)

        default:
            return .block(.untrustedCustomScheme)
        }
    }

    static func normalisedHost(_ host: String?) -> String? {
        guard var host = host?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.contains("/"), !host.contains(" "), !host.contains("@") else {
            return nil
        }
        return host
    }
}

extension NavigationContext {
    init(webKitType: WKNavigationTypeProxy) {
        switch webKitType {
        case .linkActivated: self = .linkActivated
        case .formSubmitted: self = .formSubmitted
        case .backForward: self = .backForward
        case .reload: self = .reload
        case .formResubmitted: self = .formSubmitted
        case .other: self = .other
        }
    }
}

/// A WebKit-free mirror of `WKNavigationType`, letting navigation policy tests stay pure.
enum WKNavigationTypeProxy: Equatable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
}
