import SwiftUI

@main
struct WorkbenchApp: App {
    @StateObject private var tabs = TabManager()
    @StateObject private var updater = UpdateChecker()

    var body: some Scene {
        Window("Workbench", id: "main") {
            ContentView()
                .environmentObject(tabs)
                .frame(minWidth: 820, minHeight: 540)
                .task {
                    HotKeyManager.shared.register()
                    try? await Task.sleep(for: .seconds(4))
                    await updater.check(userInitiated: false)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 880)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Buscar actualizaciones…") {
                    Task { await updater.check(userInitiated: true) }
                }
            }
            TabCommands(tabs: tabs)
        }

        Settings {
            SettingsView()
                .environmentObject(tabs)
                .environmentObject(updater)
        }
    }
}

struct TabCommands: Commands {
    @ObservedObject var tabs: TabManager

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            // ⌘1…⌘9 follow the enabled tabs in order.
            ForEach(Array(tabs.enabledTabs.prefix(9).enumerated()), id: \.element) { index, tab in
                Button(tab.label) { tabs.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button("Alternar pantalla dividida") { tabs.toggleSplit() }
                .keyboardShortcut("\\", modifiers: .command)
            Button("Gemini flotante") { FloatingGeminiPanel.shared.toggle(tabs: tabs) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Recargar pestaña activa") { tabs.reloadActive() }
                .keyboardShortcut("r", modifiers: .command)
            Divider()
        }
    }
}
