import SwiftUI
import WebKit

/// Hosts the single long-lived WKWebView. `makeUIView` must return the existing instance and
/// `dismantleUIView` must not destroy it: reparenting the same web view is fine, recreating it
/// would lose the game session and the PiP relationship.
struct CloudWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Intentionally empty: state lives in BrowserSession, not in the view.
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

    var body: some View {
        ZStack {
            ForEach(sessions) { session in
                let isActive = session.id == activeSessionID
                CloudWebView(webView: session.webView)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .disabled(!isActive)
                    .accessibilityHidden(!isActive)
            }
        }
    }
}
