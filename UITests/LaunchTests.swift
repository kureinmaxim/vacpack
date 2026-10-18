import XCTest

/// Smoke test: the app launches and shows its main window. Run with `scripts/check.sh --ui`
/// (needs Accessibility permission for the test runner the first time).
@MainActor
final class LaunchTests: XCTestCase {
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        // Match by identifier whatever element type SwiftUI exposes the view as.
        XCTAssertTrue(app.descendants(matching: .any)["dropArea"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["toolsStatus"].waitForExistence(timeout: 5))
    }
}
