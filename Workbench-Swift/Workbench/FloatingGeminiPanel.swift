import AppKit
import WebKit

/// Always-on-top Gemini panel, built directly with AppKit (NSPanel + WKWebView).
/// A plain NSPanel hosts the web view reliably; the SwiftUI Window scene
/// approach left the web view blank.
@MainActor
final class FloatingGeminiPanel {
    static let shared = FloatingGeminiPanel()
    private var panel: NSPanel?

    func toggle(tabs: TabManager) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        show(tabs: tabs)
    }

    func show(tabs: TabManager) {
        let webView = tabs.floatingGemini()
        if webView.url == nil && !webView.isLoading {
            webView.load(URLRequest(url: WorkbenchTab.gemini.url))
        }
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.title = "Gemini"
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false // keep floating while other apps are active
            p.minSize = NSSize(width: 340, height: 400)
            p.setFrameAutosaveName("GeminiFloatingPanel")
            if p.frame.origin == .zero { p.center() }
            panel = p
        }
        panel?.contentView = webView
        panel?.makeKeyAndOrderFront(nil)
    }
}
