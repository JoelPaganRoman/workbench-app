import SwiftUI

/// Same policy as the Electron app: check the latest GitHub Release tag,
/// and if it's newer offer a link to the Releases page. No silent installs.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repoOwner = "JoelPaganRoman"
    static let repoName = "workbench-app"

    @AppStorage("dismissedVersion") private var dismissedVersion: String = ""

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func check(userInitiated: Bool) async {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("Workbench-App", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            struct Release: Decodable {
                let tag_name: String?
                let html_url: String?
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = (release.tag_name ?? "").replacingOccurrences(of: "v", with: "", options: .anchored)
            guard !latest.isEmpty else { return }

            if Self.compareVersions(latest, currentVersion) > 0 {
                if !userInitiated && dismissedVersion == latest { return }
                showUpdateAlert(latest: latest,
                                releaseURL: release.html_url ?? "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases/latest")
            } else if userInitiated {
                let alert = NSAlert()
                alert.messageText = "Workbench"
                alert.informativeText = "Ya tienes la última versión (\(currentVersion))."
                alert.runModal()
            }
        } catch {
            // Offline or GitHub unreachable — silently skip, like the original.
        }
    }

    private func showUpdateAlert(latest: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Actualización disponible"
        alert.informativeText = "Hay una nueva versión de Workbench (\(latest)) disponible. Tienes la versión \(currentVersion)."
        alert.addButton(withTitle: "Descargar")
        alert.addButton(withTitle: "Más tarde")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: releaseURL) { NSWorkspace.shared.open(url) }
        } else {
            dismissedVersion = latest
        }
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let na = i < pa.count ? pa[i] : 0
            let nb = i < pb.count ? pb[i] : 0
            if na != nb { return na - nb }
        }
        return 0
    }
}
