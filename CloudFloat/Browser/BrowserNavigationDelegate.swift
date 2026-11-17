import Foundation
import WebKit

@MainActor
final class BrowserNavigationDelegate: NSObject, WKNavigationDelegate {
    private weak var session: BrowserSession?

    init(session: BrowserSession) {
        self.session = session
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let session else {
            decisionHandler(.cancel)
            return
        }
        let context = NavigationContext(webKitType: Self.proxy(for: navigationAction.navigationType))
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let decision = session.navigationPolicy.decision(
            for: navigationAction.request.url,
            context: context,
            isMainFrame: isMainFrame
        )
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .openExternally(let url):
            session.requestExternalOpen(url)
            decisionHandler(.cancel)
        case .block(let reason):
            session.recordBlockedNavigation(url: navigationAction.request.url, reason: reason)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            session?.recordHTTPError(status: response.statusCode, host: response.url?.host)
        }
        if !navigationResponse.canShowMIMEType {
            session?.recordDownloadStarted(response: navigationResponse.response)
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        session?.registerDownload(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        session?.registerDownload(download)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session?.handleNavigationStarted()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        session?.handleNavigationCommitted()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        session?.handleNavigationFinished()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        session?.handleNavigationFailure(error: error, isProvisional: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session?.handleNavigationFailure(error: error, isProvisional: false)
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        session?.recordRedirect(host: webView.url?.host)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        session?.handleWebContentProcessTermination()
    }

    /// Server-trust challenges always use system default handling. Invalid certificates cause
    /// a navigation failure that is surfaced to the user; the app never installs a bypass.
    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            session?.recordTLSChallenge(host: challenge.protectionSpace.host)
        }
        completionHandler(.performDefaultHandling, nil)
    }

    /// Deprecated TLS versions are refused rather than silently accepted.
    func webView(
        _ webView: WKWebView,
        authenticationChallenge challenge: URLAuthenticationChallenge,
        shouldAllowDeprecatedTLS decisionHandler: @escaping (Bool) -> Void
    ) {
        decisionHandler(false)
    }

    private static func proxy(for type: WKNavigationType) -> WKNavigationTypeProxy {
        switch type {
        case .linkActivated: return .linkActivated
        case .formSubmitted: return .formSubmitted
        case .backForward: return .backForward
        case .reload: return .reload
        case .formResubmitted: return .formResubmitted
        case .other: return .other
        @unknown default: return .other
        }
    }
}
