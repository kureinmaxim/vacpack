import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// UI smoke tests. Run with `scripts/check.sh --ui` (the test runner needs Accessibility
/// permission the first time).
@MainActor
final class LaunchTests: XCTestCase {
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        // Match by identifier whatever element type SwiftUI exposes the view as.
        XCTAssertTrue(app.descendants(matching: .any)["dropArea"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["compressButton"].waitForExistence(timeout: 5))
    }

    /// Adds several images, compresses them and expects every row to show its result.
    func testCompressesAddedImages() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "MyCompressorUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = try (1...5).map { try Self.writeJPEG(to: folder.appending(path: "photo\($0).jpg")) }

        let app = XCUIApplication()
        app.launchEnvironment["MYCOMPRESSOR_UITEST_FILES"] = files.map(\.path).joined(separator: ":")
        app.launch()

        let details = app.descendants(matching: .any).matching(identifier: "fileDetail")
        XCTAssertTrue(details.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(details.count, 5)
        app.descendants(matching: .any)["compressButton"].click()

        // Poll the row texts; on failure the message shows what each row says.
        var labels: [String] = []
        let deadline = Date().addingTimeInterval(60)
        repeat {
            // On macOS a SwiftUI Text exposes its string as the accessibility value, not the label.
            labels = (0..<details.count).map { index in
                let element = details.element(boundBy: index)
                return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
            }
            if labels.count == 5, labels.allSatisfy({ $0.contains("→") }) { break }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        XCTAssertTrue(labels.count == 5 && labels.allSatisfy { $0.contains("→") }, "rows: \(labels)")
        for index in 1...5 {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.appending(path: "photo\(index)_compressed.jpg").path))
        }
    }

    /// Compresses a short video through the app's video queue.
    func testCompressesVideo() throws {
        let ffmpeg = "/opt/homebrew/bin/ffmpeg"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: ffmpeg), "needs ffmpeg")
        let folder = FileManager.default.temporaryDirectory.appending(path: "MyCompressorUITest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = folder.appending(path: "clip.mp4")
        let make = Process()
        make.executableURL = URL(filePath: ffmpeg)
        make.arguments = [
            "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=2,noise=alls=10:allf=t",
            "-f", "lavfi", "-i", "sine=d=2", "-c:v", "libx264", "-crf", "12", "-c:a", "aac", clip.path,
        ]
        try make.run()
        make.waitUntilExit()
        XCTAssertEqual(make.terminationStatus, 0)

        let app = XCUIApplication()
        app.launchEnvironment["MYCOMPRESSOR_UITEST_FILES"] = clip.path
        app.launch()
        let detail = app.descendants(matching: .any).matching(identifier: "fileDetail").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        app.descendants(matching: .any)["compressButton"].click()

        var text = ""
        let deadline = Date().addingTimeInterval(60)
        repeat {
            text = (detail.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? detail.label
            if text.contains("→") { break }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        XCTAssertTrue(text.contains("→"), "row: \(text)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "clip_compressed.mp4").path))
    }

    /// A noisy high-quality JPEG that the default settings will shrink.
    static func writeJPEG(to url: URL, width: Int = 640, height: Int = 480) throws -> URL {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var seed: UInt32 = 42
        for i in 0..<(width * height * 4) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[i] = UInt8(truncatingIfNeeded: (i / 4 % width) / 3 + Int(seed >> 28))
        }
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
