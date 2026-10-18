import CompressorKit
import Foundation
import Testing

@Suite("ToolLocator")
struct ToolLocatorTests {
    /// A fresh directory with fake tool scripts, removed after the test.
    final class FakeToolDirectory {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory.appending(path: "ToolLocatorTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        @discardableResult
        func addScript(_ name: String, printing output: String = "", executable: Bool = true) throws -> URL {
            let file = url.appending(path: name)
            try "#!/bin/sh\nprintf '%s\\n' '\(output)'\n".write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: file.path)
            return file
        }
    }

    @Test func findsExecutableInSearchDirectory() throws {
        let dir = try FakeToolDirectory()
        let script = try dir.addScript("ffmpeg")
        let located = ToolLocator(searchDirectories: [dir.url]).locate(.ffmpeg)
        #expect(located == LocatedTool(tool: .ffmpeg, url: script))
    }

    @Test func ghostscriptIsLookedUpAsGs() throws {
        let dir = try FakeToolDirectory()
        let script = try dir.addScript("gs")
        #expect(ToolLocator(searchDirectories: [dir.url]).locate(.ghostscript)?.url == script)
    }

    @Test func ignoresNonExecutableFiles() throws {
        let dir = try FakeToolDirectory()
        try dir.addScript("pngquant", executable: false)
        #expect(ToolLocator(searchDirectories: [dir.url]).locate(.pngquant) == nil)
    }

    @Test func earlierDirectoryWins() throws {
        let first = try FakeToolDirectory()
        let second = try FakeToolDirectory()
        let preferred = try first.addScript("gifski")
        try second.addScript("gifski")
        #expect(ToolLocator(searchDirectories: [first.url, second.url]).locate(.gifski)?.url == preferred)
    }

    @Test func missingToolReturnsNil() throws {
        let dir = try FakeToolDirectory()
        #expect(ToolLocator(searchDirectories: [dir.url]).locate(.avifenc) == nil)
    }

    @Test func readsVersionFromFirstOutputLine() async throws {
        let dir = try FakeToolDirectory()
        try dir.addScript("ffprobe", printing: "ffprobe version 8.0 Copyright (c) the FFmpeg developers")
        let locator = ToolLocator(searchDirectories: [dir.url])
        let located = try #require(locator.locate(.ffprobe))
        #expect(try await locator.version(of: located) == "ffprobe version 8.0 Copyright (c) the FFmpeg developers")
    }

    @Test func defaultSearchOrderPrefersAppToolsThenHomebrew() {
        let paths = ToolLocator.defaultSearchDirectories.map(\.path)
        #expect(paths.first == ToolLocator.appToolsDirectory.path)
        #expect(paths.dropFirst().first == "/opt/homebrew/bin")
        #expect(paths.contains("/opt/local/bin"))
    }

    @Test(
        arguments: [
            ("10.08.0\n", "10.08.0"),
            ("\n  gifski 1.34.0  \nmore", "gifski 1.34.0"),
            ("", nil),
            ("\n\n", nil),
        ] as [(String, String?)])
    func parseVersion(output: String, expected: String?) {
        #expect(Tool.parseVersion(output) == expected)
    }
}
