import CompressorKit
import XCTest

@testable import Vacpack

/// Host-app tests: run inside Vacpack.app, so `Bundle.main` is the app bundle.
final class AppTests: XCTestCase {
    func testBundleIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "xyz.kurein.vacpack")
    }

    func testAppIsNotSandboxed() {
        // ARCHITECTURE D6: the app must reach Homebrew tools and arbitrary folders.
        XCTAssertNil(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"])
    }

    func testVersionMatchesCompressorKit() {
        // project.yml feeds Info.plist; scripts/update_version.py keeps CompressorKit's copy in sync.
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, VacpackVersion.number)
    }

    func testAboutCreditsLinkToGitHub() {
        let credits = ProjectLinks.credits(source: "abc1234", sourceDate: "pushed 18.10.2026 19:59")
        XCTAssertTrue(credits.string.contains("Commit abc1234, pushed 18.10.2026 19:59"))
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { links.append(url) }
        }
        XCTAssertEqual(links, [ProjectLinks.repository, ProjectLinks.author])
        // Debug builds carry no commit: no commit line.
        XCTAssertFalse(ProjectLinks.credits(source: "", sourceDate: "").string.contains("Commit"))
    }

    func testCompressorKitIsLinked() {
        XCTAssertEqual(Tool.ghostscript.executableName, "gs")
    }
}
