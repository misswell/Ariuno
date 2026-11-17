import Foundation
import UIKit
import WebKit

/// Presents the small set of JavaScript dialogs a login flow may use. All completions are
/// guaranteed to run, otherwise WebKit would leave the page blocked.
@MainActor
enum WebKitDialogPresenter {
    static func alert(host: String, message: String, completion: @escaping () -> Void) {
        let alert = UIAlertController(
            title: displayHost(host),
            message: String(message.prefix(1_000)),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completion() })
        present(alert) { completion() }
    }

    static func confirm(host: String, message: String, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: displayHost(host),
            message: String(message.prefix(1_000)),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completion(true) })
        present(alert) { completion(false) }
    }

    static func prompt(
        host: String,
        message: String,
        defaultText: String?,
        completion: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(
            title: displayHost(host),
            message: String(message.prefix(1_000)),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = defaultText
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in
            completion(alert?.textFields?.first?.text)
        })
        present(alert) { completion(nil) }
    }

    private static func displayHost(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "网页提示" : trimmed
    }

    private static func present(_ alert: UIAlertController, fallback: @escaping () -> Void) {
        DispatchQueue.main.async {
            guard let presenter = ViewControllerLocator.topmost() else {
                fallback()
                return
            }
            presenter.present(alert, animated: true)
        }
    }
}

@MainActor
enum ViewControllerLocator {
    static func topmost() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

@MainActor
final class BrowserUIDelegate: NSObject, WKUIDelegate {
    private weak var session: BrowserSession?

    init(session: BrowserSession) {
        self.session = session
        super.init()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let session else { return nil }

        return session.handleCreateWindow(
            configuration: configuration,
            navigationAction: navigationAction
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        session?.requestClose()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        WebKitDialogPresenter.alert(
            host: frame.securityOrigin.host,
            message: message,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        WebKitDialogPresenter.confirm(
            host: frame.securityOrigin.host,
            message: message,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        WebKitDialogPresenter.prompt(
            host: frame.securityOrigin.host,
            message: prompt,
            defaultText: defaultText,
            completion: completionHandler
        )
    }

    @available(iOS 18.4, *)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        var picker: UIDocumentPickerViewController?
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker?.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker?.delegate = FileUploadPickerDelegate.shared
        FileUploadPickerDelegate.shared.completionHandler = completionHandler
        ViewControllerLocator.topmost()?.present(picker!, animated: true)
    }

    /// The cloud game does not need camera/microphone access. Deny by default so a page
    /// cannot silently request capture permission.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        session?.recordMediaCaptureDenied(host: origin.host)
        decisionHandler(.deny)
    }
}

@MainActor
final class FileUploadPickerDelegate: NSObject, UIDocumentPickerDelegate {
    static let shared = FileUploadPickerDelegate()
    var completionHandler: (([URL]?) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completionHandler?(urls)
        completionHandler = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completionHandler?(nil)
        completionHandler = nil
    }
}

@MainActor
final class PopupNavigationDelegate: NSObject, WKNavigationDelegate {
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
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let decision = session.navigationPolicy.decision(
            for: url,
            context: .other,
            isMainFrame: true
        )
        switch decision {
        case .allow:
            decisionHandler(.allow)
        case .openExternally(let external):
            session.requestExternalOpen(external)
            decisionHandler(.cancel)
        case .block(let reason):
            session.recordBlockedNavigation(url: url, reason: reason)
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        session?.recordPopupNavigationFailure(error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        session?.recordPopupNavigationFailure(error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        session?.handlePopupProcessTermination()
    }

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

    func webView(
        _ webView: WKWebView,
        authenticationChallenge challenge: URLAuthenticationChallenge,
        shouldAllowDeprecatedTLS decisionHandler: @escaping (Bool) -> Void
    ) {
        decisionHandler(false)
    }
}

@MainActor
final class PopupUIDelegate: NSObject, WKUIDelegate {
    private weak var session: BrowserSession?

    init(session: BrowserSession) {
        self.session = session
        super.init()
    }

    func webViewDidClose(_ webView: WKWebView) {
        session?.closePopup()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Nested popups are not needed for login and would be hard to manage.
        nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        WebKitDialogPresenter.alert(
            host: frame.securityOrigin.host,
            message: message,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        WebKitDialogPresenter.confirm(
            host: frame.securityOrigin.host,
            message: message,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        WebKitDialogPresenter.prompt(
            host: frame.securityOrigin.host,
            message: prompt,
            defaultText: defaultText,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }
}
