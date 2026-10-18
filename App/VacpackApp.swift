import AppKit
import CompressorKit
import SwiftUI

@main
struct VacpackApp: App {
    var body: some Scene {
        WindowGroup("Vacpack") {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vacpack") { showAboutPanel() }
            }
        }
    }

    /// The standard About panel with the release date next to the version:
    /// "Version 0.1.0, released 18.10.2026 (build 20261018.143629)".
    private func showAboutPanel() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(VacpackVersion.number), released \(VacpackVersion.releaseDate)",
            .version: "build \(build)",
        ])
    }
}
