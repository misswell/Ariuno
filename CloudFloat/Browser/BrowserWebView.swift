import UIKit
import WebKit

/// WKWebView exposes its `safeAreaInsets` to page CSS via `env(safe-area-inset-*)`.
/// When the web view is mounted edge-to-edge under our floating chrome, UIKit reports zero;
/// override it with the browser's real safe area so fixed headers and bottom sheets can avoid
/// the status bar and home indicator.
final class BrowserWebView: WKWebView {
    var pageSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        pageSafeAreaInsets
    }
}
