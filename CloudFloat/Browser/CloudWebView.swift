import SwiftUI
import WebKit

/// Hosts the single long-lived WKWebView. `makeUIView` must return the existing instance and
/// `dismantleUIView` must not destroy it: reparenting the same web view is fine, recreating it
/// would lose the game session and the PiP relationship.
struct CloudWebView: UIViewRepresentable {
    let webView: WKWebView
    /// Safari-like safe areas: content is inset at rest but can scroll under the status bar
    /// and behind the floating bottom chrome.
    var topContentInset: CGFloat = 0
    var bottomContentInset: CGFloat = 0

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let top = max(0, topContentInset)
        let bottom = max(0, bottomContentInset)
        guard abs(uiView.scrollView.contentInset.top - top) > 0.5
                || abs(uiView.scrollView.contentInset.bottom - bottom) > 0.5 else { return }
        var inset = uiView.scrollView.contentInset
        inset.top = top
        inset.bottom = bottom
        uiView.scrollView.contentInset = inset
        uiView.scrollView.verticalScrollIndicatorInsets.top = top
        uiView.scrollView.verticalScrollIndicatorInsets.bottom = bottom
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        // No-op. BrowserSession owns the web view lifetime.
    }
}


/// Keeps every tab's WKWebView mounted so switching tabs neither recreates the WebView nor
/// reloads the page. Inactive tabs are hidden and non-interactive but remain alive.
struct BrowserTabHostView: View {
    let sessions: [BrowserSession]
    let activeSessionID: UUID
    var topContentInset: CGFloat = 0
    var bottomContentInset: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(sessions) { session in
                let isActive = session.id == activeSessionID
                CloudWebView(
                    webView: session.webView,
                    topContentInset: topContentInset,
                    bottomContentInset: bottomContentInset
                )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .disabled(!isActive)
                    .accessibilityHidden(!isActive)
            }
        }
    }
}
