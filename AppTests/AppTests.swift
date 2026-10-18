import CompressorKit
import XCTest

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

    func testCompressorKitIsLinked() {
        XCTAssertEqual(Tool.ghostscript.executableName, "gs")
    }
}
