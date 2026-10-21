import AppKit
import CompressorKit
import SwiftUI

@main
struct VacpackApp: App {
    init() {
        InterfaceLanguage.apply()
        #if DEBUG
            WindowSnapshot.applyAppearance()
        #endif
    }

    var body: some Scene {
        WindowGroup("Vacpack") {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Vacpack") { showAboutPanel() }
            }
            CommandGroup(after: .appInfo) {
                Menu("Language") {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { language in
                        Toggle(
                            language.title,
                            isOn: Binding(
                                get: { InterfaceLanguage.current == language },
                                set: { _ in InterfaceLanguage.choose(language) }))
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Button("Vacpack on GitHub") { NSWorkspace.shared.open(ProjectLinks.repository) }
                Button("Release Notes") { NSWorkspace.shared.open(ProjectLinks.changelog) }
                Button("Report an Issue") { NSWorkspace.shared.open(ProjectLinks.issues) }
                Divider()
                Button("Author on GitHub") { NSWorkspace.shared.open(ProjectLinks.author) }
            }
        }
    }

    /// The standard About panel with the release date next to the version,
    /// "Version 0.2.0, released 18.10.2026 (build 20261018.143629)", and links in the credits.
    private func showAboutPanel() {
        let info = Bundle.main.infoDictionary ?? [:]
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "\(VacpackVersion.number), released \(VacpackVersion.releaseDate)",
            .version: "build \(info["CFBundleVersion"] as? String ?? "?")",
            .credits: ProjectLinks.credits(
                source: info["VacpackSource"] as? String, sourceDate: info["VacpackSourceDate"] as? String),
        ])
    }
}

/// Where Vacpack lives on GitHub.
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/kureinmaxim/vacpack")!
    static let author = URL(string: "https://github.com/kureinmaxim")!
    static let issues = repository.appending(path: "issues")
    static let changelog = repository.appending(path: "blob/main/CHANGELOG.md")

    /// The About panel's credits: the project and its author as links, then the commit the build
    /// came from and when it was pushed (stamped by scripts/package.sh; empty in Debug builds).
    static func credits(source: String?, sourceDate: String?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 3
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString()
        func add(_ string: String, link: URL? = nil) {
            var attributes = plain
            if let link { attributes[.link] = link }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        add(String(localized: "Project: "))
        add("github.com/kureinmaxim/vacpack", link: repository)
        add("\n" + String(localized: "Author: "))
        add("github.com/kureinmaxim", link: author)
        if let source, !source.isEmpty {
            add("\n" + String(localized: "Commit \(source)") + (sourceDate.map { $0.isEmpty ? "" : ", \($0)" } ?? ""))
        }
        add("\n" + String(localized: "Free software under the GNU GPL v3"))
        return text
    }
}

/// The interface language: English unless the user picks Russian. macOS reads `AppleLanguages` once
/// per launch, so a change takes effect after a restart.
enum InterfaceLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"

    private static let key = "VacpackLanguage"

    /// Each language in its own tongue, so it can be found whatever the current one is.
    var title: String { self == .english ? "English" : "Русский" }

    static var current: InterfaceLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(InterfaceLanguage.init) ?? .english
    }

    /// Call before the first window: the bundle then looks strings up in the chosen language,
    /// whatever the system language is.
    static func apply() {
        UserDefaults.standard.set([current.rawValue], forKey: "AppleLanguages")
    }

    @MainActor static func choose(_ language: InterfaceLanguage) {
        guard language != current else { return }
        UserDefaults.standard.set(language.rawValue, forKey: key)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart Vacpack to change the language?")
        alert.addButton(withTitle: String(localized: "Restart"))
        alert.addButton(withTitle: String(localized: "Later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
