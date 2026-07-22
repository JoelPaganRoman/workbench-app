import SwiftUI
import WebKit
import UserNotifications

@MainActor
final class TabManager: NSObject, ObservableObject {
    @Published var leftPane: WorkbenchTab {
        didSet { UserDefaults.standard.set(leftPane.rawValue, forKey: "leftPane") }
    }
    @Published var rightPane: WorkbenchTab? {
        didSet { UserDefaults.standard.set(rightPane?.rawValue ?? "", forKey: "rightPane") }
    }
    @Published var splitMode: Bool {
        didSet { UserDefaults.standard.set(splitMode, forKey: "splitMode") }
    }
    /// 0…1 page-load progress per tab, driving the thin bar under the tab bar.
    @Published var progress: [WorkbenchTab: Double] = [:]

    @AppStorage("splitRatio") var splitRatio: Double = 0.5
    @AppStorage("tabPosition") var tabPositionRaw: String = "top"
    @AppStorage("enabledTabs") var enabledTabsRaw: String = WorkbenchTab.defaultEnabled

    var tabPosition: TabPosition { TabPosition(rawValue: tabPositionRaw) ?? .top }

    var enabledTabs: [WorkbenchTab] {
        let set = Set(enabledTabsRaw.split(separator: ",").map(String.init))
        let tabs = WorkbenchTab.allCases.filter { set.contains($0.rawValue) }
        return tabs.isEmpty ? [.docs] : tabs
    }

    func isEnabled(_ tab: WorkbenchTab) -> Bool { enabledTabs.contains(tab) }

    func setEnabled(_ tab: WorkbenchTab, _ enabled: Bool) {
        var current = enabledTabs
        if enabled {
            if !current.contains(tab) { current.append(tab) }
        } else {
            guard current.count > 1 else { return } // always keep at least one tab
            current.removeAll { $0 == tab }
            // Don't leave a disabled tab on screen.
            if leftPane == tab { leftPane = current[0] }
            if rightPane == tab { splitMode ? closeSplit() : (rightPane = nil) }
        }
        enabledTabsRaw = WorkbenchTab.allCases.filter { current.contains($0) }
            .map(\.rawValue).joined(separator: ",")
        objectWillChange.send()
    }

    static let minRatio = 0.15
    static let maxRatio = 0.85

    private var webViews: [WorkbenchTab: WKWebView] = [:]
    private var observations: [NSKeyValueObservation] = []
    private var pendingDownloads: [ObjectIdentifier: URL] = [:]
    private var notificationPermissionRequested = false

    override init() {
        let defaults = UserDefaults.standard
        leftPane = WorkbenchTab(rawValue: defaults.string(forKey: "leftPane") ?? "") ?? .docs
        rightPane = WorkbenchTab(rawValue: defaults.string(forKey: "rightPane") ?? "")
        splitMode = defaults.bool(forKey: "splitMode") && defaults.string(forKey: "rightPane")?.isEmpty == false
        super.init()
        if !isEnabled(leftPane) { leftPane = enabledTabs[0] }
        if let right = rightPane, !isEnabled(right) { splitMode = false; rightPane = nil }
    }

    // MARK: - Web views

    /// All tabs share one data store so a single Google sign-in covers
    /// every tab — the equivalent of Electron's persist:googleworkspace partition.
    private func makeWebView(url: URL) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/17.4 Safari/605.1.15"
        // Bridge the Web Notification API to native macOS notifications:
        // pages call new Notification(...) and we forward it to UNUserNotificationCenter.
        let script = """
        (function () {
          if (window.__wbNativeNotification) return;
          window.__wbNativeNotification = true;
          const NativeNotification = function (title, options) {
            try {
              window.webkit.messageHandlers.wbNotify.postMessage({
                title: String(title || ''),
                body: String((options && options.body) || '')
              });
            } catch (e) {}
            this.close = function () {};
            this.onclick = null;
          };
          NativeNotification.permission = 'granted';
          NativeNotification.requestPermission = function (cb) {
            if (cb) cb('granted');
            return Promise.resolve('granted');
          };
          window.Notification = NativeNotification;
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(self, name: "wbNotify")

        // A non-zero initial frame — WKWebView can stall its first paint when
        // created at zero size and shown in a window that opens later.
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func webView(for tab: WorkbenchTab) -> WKWebView {
        if let existing = webViews[tab] { return existing }
        let view = makeWebView(url: tab.url)
        webViews[tab] = view
        observations.append(view.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            let value = wv.estimatedProgress
            Task { @MainActor in self?.progress[tab] = value }
        })
        observations.append(view.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            let loading = wv.isLoading
            Task { @MainActor in if !loading { self?.progress[tab] = 1 } }
        })
        return view
    }

    /// Dedicated Gemini instance for the floating window, so it can stay
    /// open while the Gemini tab is also visible in the main window.
    private var floatingGeminiView: WKWebView?
    func floatingGemini() -> WKWebView {
        if let existing = floatingGeminiView { return existing }
        let view = makeWebView(url: WorkbenchTab.gemini.url)
        floatingGeminiView = view
        return view
    }

    private func tab(owning webView: WKWebView) -> WorkbenchTab? {
        // The floating panel behaves as a Gemini tab so the link interceptor
        // never cancels its own navigation (that left the panel blank).
        if webView === floatingGeminiView { return .gemini }
        return webViews.first(where: { $0.value === webView })?.key
    }

    // MARK: - Panes

    func select(_ tab: WorkbenchTab) { setPane(.left, to: tab) }

    enum Pane { case left, right }

    func setPane(_ pane: Pane, to tab: WorkbenchTab, url: URL? = nil) {
        // Swap instead of showing the same tab in both panes.
        switch pane {
        case .left:
            if rightPane == tab { rightPane = leftPane }
            leftPane = tab
        case .right:
            if leftPane == tab { leftPane = rightPane ?? leftPane }
            rightPane = tab
        }
        let view = webView(for: tab)
        if let url { view.load(URLRequest(url: url)) }
    }

    func toggleSplit() {
        splitMode.toggle()
        if splitMode && rightPane == nil {
            rightPane = enabledTabs.first { $0 != leftPane } ?? .docs
        }
    }

    func closeSplit() {
        splitMode = false
        rightPane = nil
    }

    func reloadActive() {
        webViews[leftPane]?.reload()
    }

    /// A link belonging to another tab opens in that tab (in the opposite
    /// pane when split), instead of navigating the current web view away.
    private func open(_ tab: WorkbenchTab, url: URL, from source: WorkbenchTab?) {
        if splitMode {
            let sourceIsLeft = (source == leftPane)
            setPane(sourceIsLeft ? .right : .left, to: tab, url: url)
        } else {
            setPane(.left, to: tab, url: url)
        }
    }
}

enum TabPosition: String {
    case top, left
}

// MARK: - Navigation & downloads

extension TabManager: WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        MainActor.assumeIsolated {
            let source = tab(owning: webView)
            let (target, resolved) = WorkbenchTab.classify(url)
            if navigationAction.targetFrame?.isMainFrame != false,
               let target, target != source, isEnabled(target) {
                open(target, url: resolved, from: source)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    // Anything the web view can't render inline (exports, Drive downloads…)
    // becomes a download into ~/Downloads.
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    nonisolated func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        MainActor.assumeIsolated { download.delegate = self }
    }

    nonisolated func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        MainActor.assumeIsolated { download.delegate = self }
    }

    nonisolated func download(_ download: WKDownload,
                              decideDestinationUsing response: URLResponse,
                              suggestedFilename: String,
                              completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)")
            counter += 1
        }
        let destination = dest
        MainActor.assumeIsolated { pendingDownloads[ObjectIdentifier(download)] = destination }
        completionHandler(destination)
    }

    nonisolated func downloadDidFinish(_ download: WKDownload) {
        MainActor.assumeIsolated {
            if let url = pendingDownloads.removeValue(forKey: ObjectIdentifier(download)) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    nonisolated func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        MainActor.assumeIsolated {
            pendingDownloads.removeValue(forKey: ObjectIdentifier(download))
        }
    }

    // target="_blank" / window.open: route Google links to their tab,
    // everything else to the default browser. Never spawn a new window.
    nonisolated func webView(_ webView: WKWebView,
                             createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction,
                             windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        MainActor.assumeIsolated {
            let source = tab(owning: webView)
            let (target, resolved) = WorkbenchTab.classify(url)
            if let target, isEnabled(target) || target == source {
                if target == source {
                    webView.load(URLRequest(url: resolved))
                } else {
                    open(target, url: resolved, from: source)
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }
}

// MARK: - Web Notification bridge

extension TabManager: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard message.name == "wbNotify",
              let payload = message.body as? [String: Any],
              let title = payload["title"] as? String, !title.isEmpty else { return }
        let body = payload["body"] as? String ?? ""
        MainActor.assumeIsolated {
            deliverNotification(title: title, body: body)
        }
    }

    private func deliverNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let post = {
            let content = UNMutableNotificationContent()
            content.title = title
            if !body.isEmpty { content.body = body }
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if notificationPermissionRequested {
            post()
        } else {
            notificationPermissionRequested = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted { post() }
            }
        }
    }
}
