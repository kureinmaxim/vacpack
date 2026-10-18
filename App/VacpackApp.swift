import AppKit
import CompressorKit
import SwiftUI

@main
struct VacpackApp: App {
    init() {
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
        add("Project: ")
        add("github.com/kureinmaxim/vacpack", link: repository)
        add("\nAuthor: ")
        add("github.com/kureinmaxim", link: author)
        if let source, !source.isEmpty {
            add("\nCommit \(source)" + (sourceDate.map { $0.isEmpty ? "" : ", \($0)" } ?? ""))
        }
        add("\nFree software under the GNU GPL v3")
        return text
    }
}
