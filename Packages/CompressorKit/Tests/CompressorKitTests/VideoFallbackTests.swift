import Foundation
import Testing

@testable import CompressorKit

/// VideoToolbox can refuse a session when the media engine is busy. These tests use fake
/// ffprobe/ffmpeg scripts: the fake ffmpeg logs every call and fails whenever it is asked to
/// encode with VideoToolbox, as the real one does with error -22.
@Suite(
    "Video fallback",
    .enabled(
        if: VideoEngine(ffmpeg: nil, ffprobe: nil).environment.videoToolboxQuality,
        "VideoToolbox quality mode exists only on Apple Silicon"))
struct VideoFallbackTests {
    let dir = TempDirectory("VideoFallback")
    var log: URL { dir.file("calls.log") }

    /// Writes an executable script and returns its URL.
    func script(_ name: String, _ body: String) throws -> URL {
        let url = dir.file(name)
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func fakeTools(codec: String, pixelFormat: String) throws -> (ffmpeg: URL, ffprobe: URL) {
        let json = """
            {"streams":[{"codec_type":"video","codec_name":"\(codec)","width":640,"height":360,"pix_fmt":"\(pixelFormat)",\
            "avg_frame_rate":"30/1"},{"codec_type":"audio","codec_name":"aac"}],"format":{"duration":"2"}}
            """
        let ffprobe = try script("ffprobe", "cat <<'JSON'\n\(json)\nJSON")
        let ffmpeg = try script(
            "ffmpeg",
            """
            echo "$*" >> '\(log.path)'
            case "$*" in
              *_videotoolbox*) echo "[vost#0:0/h264_videotoolbox] Task finished with error code: -22 (Invalid argument)" >&2; exit 1 ;;
            esac
            for last; do :; done
            printf 'fake' > "$last"
            echo "out_time_us=2000000"
            echo "progress=end"
            """)
        return (ffmpeg, ffprobe)
    }

    func calls() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    func encode(_ engine: VideoEngine, input: URL, _ settings: VideoSettings) async throws -> EncodedFile {
        let work = dir.file("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return try await engine.encode(
            input, settings: settings, options: VideoEncodingOptions(), workDirectory: work, progress: { _ in })
    }

    @Test func busyVideoToolboxFallsBackToSoftware() async throws {
        let tools = try fakeTools(codec: "h264", pixelFormat: "yuv420p")
        let input = dir.file("clip.mp4")
        try Data([0]).write(to: input)

        let encoded = try await encode(
            VideoEngine(ffmpeg: tools.ffmpeg, ffprobe: tools.ffprobe), input: input, VideoSettings())
        #expect(try String(contentsOf: encoded.url, encoding: .utf8) == "fake")
        let calls = try calls()
        #expect(calls.count == 2)
        #expect(calls[0].contains("h264_videotoolbox"))
        #expect(calls[1].contains("libx264"))
    }

    @Test func transparentMOVRetriesOnceThenReportsTheError() async throws {
        let tools = try fakeTools(codec: "prores", pixelFormat: "yuva444p10le")
        let input = dir.file("alpha.mov")
        try Data([0]).write(to: input)

        let engine = VideoEngine(ffmpeg: tools.ffmpeg, ffprobe: tools.ffprobe)
        await #expect(throws: VideoError.self) {
            _ = try await encode(engine, input: input, VideoSettings(preserveTransparency: true))
        }
        let calls = try calls()
        #expect(calls.count == 2, "one retry, no software fallback for HEVC with alpha")
        #expect(calls.allSatisfy { $0.contains("hevc_videotoolbox") && $0.contains("-alpha_quality") })
    }

    @Test func otherFailuresAreNotRetried() async throws {
        let tools = try fakeTools(codec: "h264", pixelFormat: "yuv420p")
        let input = dir.file("clip.mp4")
        try Data([0]).write(to: input)
        // Software encoding from the start: the fake succeeds, so exactly one call.
        let work = dir.file("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        _ = try await VideoEngine(ffmpeg: tools.ffmpeg, ffprobe: tools.ffprobe).encode(
            input, settings: VideoSettings(), options: VideoEncodingOptions(hardwareAcceleration: false),
            workDirectory: work, progress: { _ in })
        #expect(try calls().count == 1)
    }
}
