import SwiftUI
import WebKit

/// Hosts a long-lived WKWebView owned by TabManager, so switching tabs
/// never reloads the page.
struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
