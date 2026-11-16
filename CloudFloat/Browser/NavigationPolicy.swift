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
    case insecureHTTP
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

/// Applies the browser's navigation allow-list and external-link handoff rules. Pure
/// Foundation so every branch is unit-testable without WebKit.
struct NavigationPolicy: Equatable {
    static let officialDomainSuffixes = [
        "mihoyo.com",
        "hoyoverse.com",
        "hoyolab.com",
        "yuanshen.com"
    ]

    /// Known authentication providers may legitimately redirect inside the web view.
    static let partnerDomainSuffixes = [
        "apple.com",
        "icloud.com",
        "google.com",
        "googleapis.com",
        "gstatic.com",
        "facebook.com",
        "twitter.com",
        "x.com",
        "taptap.com",
        "taptap.cn",
        "microsoftonline.com",
        "live.com"
    ]

    var allowsLocalTestPages: Bool = false
    var localTestHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]
    var localTestPorts: Set<Int> = []
    var allowedFileDirectory: URL?

    var isEmptyAllowList: Bool {
        Self.officialDomainSuffixes.isEmpty
    }

    func isOfficial(host: String?) -> Bool {
        guard let host = NavigationPolicy.normalisedHost(host) else { return false }
        return Self.officialDomainSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

    func isAllowedPartner(host: String?) -> Bool {
        guard let host = NavigationPolicy.normalisedHost(host) else { return false }
        return Self.partnerDomainSuffixes.contains { suffix in
            host == suffix || host.hasSuffix("." + suffix)
        }
    }

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
            // WebKit uses nil/empty requests for about:blank popups internally.
            return .allow
        }
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "about":
            return .allow

        case "https", "http":
            if scheme == "http" {
                if isLocalTestURL(url) {
                    return .allow
                }
                return .block(.insecureHTTP)
            }
            if isLocalTestURL(url) {
                return .allow
            }
            if isMainFrame,
               context == .linkActivated,
               !isOfficial(host: url.host),
               !isAllowedPartner(host: url.host) {
                return .openExternally(url)
            }
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

        case "javascript", "data", "blob", "filesystem":
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
