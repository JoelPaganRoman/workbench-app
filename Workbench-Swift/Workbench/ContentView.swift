import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tabs: TabManager

    var body: some View {
        Group {
            if tabs.tabPosition == .left {
                HStack(spacing: 0) {
                    TabBar(vertical: true)
                        .frame(width: 68)
                    contentArea
                }
            } else {
                VStack(spacing: 0) {
                    TabBar(vertical: false)
                        .frame(height: 48)
                    contentArea
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 0) {
            LoadProgressBar()
            if tabs.splitMode, let right = tabs.rightPane {
                SplitContent(left: tabs.leftPane, right: right)
            } else {
                WebView(webView: tabs.webView(for: tabs.leftPane))
                    .id(tabs.leftPane)
            }
        }
    }
}

/// Thin progress strip under the tab bar while the active tab loads.
struct LoadProgressBar: View {
    @EnvironmentObject var tabs: TabManager

    var body: some View {
        let value = tabs.progress[tabs.leftPane] ?? 1
        GeometryReader { geo in
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: geo.size.width * value)
                .animation(.easeOut(duration: 0.2), value: value)
        }
        .frame(height: value < 1 ? 2 : 0)
        .opacity(value < 1 ? 1 : 0)
    }
}

struct SplitContent: View {
    @EnvironmentObject var tabs: TabManager
    let left: WorkbenchTab
    let right: WorkbenchTab
    @State private var dragStartRatio: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let ratio = min(TabManager.maxRatio, max(TabManager.minRatio, tabs.splitRatio))
            let firstWidth = width * ratio
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    PaneBar(pane: .left, current: left)
                    WebView(webView: tabs.webView(for: left))
                        .id(left)
                }
                .frame(width: max(0, firstWidth - 3))
                divider(totalWidth: width)
                VStack(spacing: 0) {
                    PaneBar(pane: .right, current: right)
                    WebView(webView: tabs.webView(for: right))
                        .id(right)
                }
            }
        }
    }

    private func divider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 6)
            .overlay(Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartRatio == nil { dragStartRatio = tabs.splitRatio }
                        let newRatio = (dragStartRatio ?? 0.5) + value.translation.width / totalWidth
                        tabs.splitRatio = min(TabManager.maxRatio, max(TabManager.minRatio, newRatio))
                    }
                    .onEnded { _ in dragStartRatio = nil }
            )
    }
}

/// Per-pane tab strip shown only in split mode, so each pane's content can
/// be changed independently — the equivalent of Electron's second bar row.
struct PaneBar: View {
    @EnvironmentObject var tabs: TabManager
    let pane: TabManager.Pane
    let current: WorkbenchTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.enabledTabs) { tab in
                Button {
                    tabs.setPane(pane, to: tab)
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tab == current ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .foregroundStyle(tab == current ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(tab.label)
            }
            Spacer()
            if pane == .right {
                Button {
                    tabs.closeSplit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Cerrar pantalla dividida")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(.thinMaterial)
    }
}

struct TabBar: View {
    @EnvironmentObject var tabs: TabManager
    let vertical: Bool

    var body: some View {
        let items = ForEach(tabs.enabledTabs) { tab in
            TabButton(tab: tab, vertical: vertical)
        }
        Group {
            if vertical {
                VStack(spacing: 6) {
                    Spacer().frame(height: 34) // clear the traffic lights
                    items
                    Spacer()
                    floatingGeminiButton
                    splitButton
                    Spacer().frame(height: 10)
                }
            } else {
                HStack(spacing: 8) {
                    Spacer().frame(width: 78) // clear the traffic lights
                    items
                    Spacer()
                    floatingGeminiButton
                    splitButton
                    Spacer().frame(width: 12)
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private var splitButton: some View {
        Button {
            tabs.toggleSplit()
        } label: {
            Image(systemName: tabs.splitMode ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tabs.splitMode ? Color.accentColor : .secondary)
        .help(tabs.splitMode ? "Cerrar pantalla dividida (⌘\\)" : "Pantalla dividida (⌘\\)")
    }

    private var floatingGeminiButton: some View {
        Button {
            FloatingGeminiPanel.shared.toggle(tabs: tabs)
        } label: {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Gemini flotante (⇧⌘G)")
    }
}

struct TabButton: View {
    @EnvironmentObject var tabs: TabManager
    let tab: WorkbenchTab
    let vertical: Bool

    private var isActive: Bool {
        tabs.leftPane == tab || (tabs.splitMode && tabs.rightPane == tab)
    }

    var body: some View {
        Button {
            tabs.select(tab)
        } label: {
            Group {
                if vertical {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol).font(.system(size: 16, weight: .medium))
                        Text(tab.label).font(.system(size: 9))
                    }
                    .frame(width: 56, height: 46)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 13, weight: .medium))
                        Text(tab.label).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? Color.accentColor.opacity(0.18) : .clear)
            )
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
