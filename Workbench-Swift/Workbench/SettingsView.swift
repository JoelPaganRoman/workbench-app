import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tabs: TabManager
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        Form {
            Picker("Posición de pestañas:", selection: $tabs.tabPositionRaw) {
                Text("Arriba").tag("top")
                Text("Izquierda").tag("left")
            }
            .pickerStyle(.radioGroup)

            Divider().padding(.vertical, 8)

            Section {
                Text("Pestañas visibles:")
                ForEach(WorkbenchTab.allCases) { tab in
                    Toggle(isOn: Binding(
                        get: { tabs.isEnabled(tab) },
                        set: { tabs.setEnabled(tab, $0) }
                    )) {
                        Label(tab.label, systemImage: tab.symbol)
                    }
                }
            }

            Divider().padding(.vertical, 8)

            Text("Atajo global: ⌥⌘W muestra u oculta Workbench desde cualquier app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 8)

            HStack {
                Text("Versión \(updater.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Buscar actualizaciones…") {
                    Task { await updater.check(userInitiated: true) }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
