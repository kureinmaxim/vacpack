import Foundation

/// External command-line tools the compression engines rely on.
public enum Tool: String, CaseIterable, Sendable {
    case ffmpeg, ffprobe, pngquant, gifski, cwebp, avifenc, ghostscript

    /// File name of the executable on disk.
    public var executableName: String {
        switch self {
        case .ghostscript: "gs"
        default: rawValue
        }
    }

    /// Arguments that make the tool print its version and exit.
    public var versionArguments: [String] {
        switch self {
        case .ffmpeg, .ffprobe, .cwebp: ["-version"]
        case .pngquant, .gifski, .avifenc, .ghostscript: ["--version"]
        }
    }

    /// The first non-empty line of the tool's version output, trimmed.
    public static func parseVersion(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

/// A tool found on disk.
public struct LocatedTool: Sendable, Equatable {
    public let tool: Tool
    public let url: URL

    public init(tool: Tool, url: URL) {
        self.tool = tool
        self.url = url
    }
}

/// Finds tools by absolute path in a fixed list of directories.
///
/// The user's shell is never consulted: aliases and `PATH` from shell profiles do not
/// apply (for example, `gs` is often an alias for `git status`).
public struct ToolLocator: Sendable {
    public let searchDirectories: [URL]

    public init(searchDirectories: [URL] = ToolLocator.defaultSearchDirectories) {
        self.searchDirectories = searchDirectories
    }

    /// Tools installed by the app first, then Homebrew (Apple Silicon, Intel), then MacPorts.
    public static var defaultSearchDirectories: [URL] {
        [
            appToolsDirectory,
            URL(filePath: "/opt/homebrew/bin"),
            URL(filePath: "/usr/local/bin"),
            URL(filePath: "/opt/local/bin"),
        ]
    }

    /// Where the release build installs its pinned tools (see ARCHITECTURE D7).
    public static var appToolsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Vacpack/tools", directoryHint: .isDirectory)
    }

    /// The first executable named like the tool in the search directories, or nil.
    public func locate(_ tool: Tool) -> LocatedTool? {
        for directory in searchDirectories {
            let candidate = directory.appending(path: tool.executableName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                // Keep the symlink: Homebrew's bin path stays valid across upgrades, the Cellar path does not.
                return LocatedTool(tool: tool, url: candidate)
            }
        }
        return nil
    }

    /// Runs the tool's version command and returns its first output line.
    public func version(
        of located: LocatedTool, runner: ProcessRunner = ProcessRunner(), timeout: Duration = .seconds(10)
    ) async throws -> String? {
        let result = try await runner.run(located.url, arguments: located.tool.versionArguments, timeout: timeout)
        // Some tools print the version to stderr.
        return Tool.parseVersion(result.stdoutString) ?? Tool.parseVersion(result.stderrString)
    }
}
