import Foundation
import Testing

@testable import CompressorKit

let videoTools = (ffmpeg: ToolLocator().locate(.ffmpeg)?.url, ffprobe: ToolLocator().locate(.ffprobe)?.url)
let videoToolsInstalled = videoTools.ffmpeg != nil && videoTools.ffprobe != nil

/// Test clips, generated once per test run with ffmpeg.
enum VideoFixtures {
    static let shared = Task { try await generate() }

    struct Clips: Sendable {
        let directory: URL
        func url(_ name: String) -> URL { directory.appending(path: name) }
    }

    /// Bump when the clips below change, so a stale cache is not reused.
    static let version = 2

    /// Reuses clips from an earlier run; otherwise generates them into a scratch folder and
    /// renames it into place, so a half-written cache is never used.
    static func generate() async throws -> Clips {
        let cache = FileManager.default.temporaryDirectory.appending(path: "VacpackVideoFixtures-v\(version)")
        if FileManager.default.fileExists(atPath: cache.appending(path: "long.mp4").path) {
            return Clips(directory: cache)
        }
        let scratch = try await generate(
            into: cache.deletingLastPathComponent().appending(path: "\(cache.lastPathComponent)-\(UUID().uuidString)"))
        do {
            try FileManager.default.moveItem(at: scratch, to: cache)
        } catch {
            // Another run won the race; use its copy.
            try? FileManager.default.removeItem(at: scratch)
        }
        return Clips(directory: cache)
    }

    private static func generate(into dir: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let runner = ProcessRunner()
        func ff(_ args: [String]) async throws {
            _ = try await runner.run(
                videoTools.ffmpeg!, arguments: ["-hide_banner", "-loglevel", "error", "-y"] + args,
                timeout: .seconds(120)
            ).checked()
        }
        let pattern = "testsrc2=size=640x360:rate=30:duration=2,noise=alls=10:allf=t"
        let path = { (name: String) in dir.appending(path: name).path }
        // High-quality H.264 + AAC stereo: the default settings shrink it.
        try await ff([
            "-f", "lavfi", "-i", pattern, "-f", "lavfi", "-i", "sine=f=440:d=2", "-ac", "2", "-c:v", "libx264", "-crf",
            "12",
            "-pix_fmt", "yuv420p", "-c:a", "aac", path("normal.mp4"),
        ])
        try await ff(["-i", path("normal.mp4"), "-an", "-c:v", "copy", path("noaudio.mp4")])
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30:duration=2", "-f", "lavfi", "-i", "sine=f=440:d=2",
            "-f", "lavfi", "-i", "sine=f=880:d=2", "-map", "0", "-map", "1", "-map", "2", "-c:v", "libx264", "-crf",
            "12",
            "-c:a", "aac", path("twoaudio.mov"),
        ])
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30:duration=1", "-f", "lavfi", "-i", "sine=f=440:d=1",
            "-c:v", "libx264", "-crf", "12", "-c:a", "pcm_s16le", path("pcm.mov"),
        ])
        // Odd size needs a codec without 4:2:0 limits: FFV1 in Matroska.
        try await ff(["-f", "lavfi", "-i", "testsrc2=size=321x241:rate=25:duration=1", "-c:v", "ffv1", path("odd.mkv")])
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30:duration=1,format=rgba,colorchannelmixer=aa=0.5",
            "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", path("alpha.mov"),
        ])
        try await ff([
            "-i", path("alpha.mov"), "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-crf", "20", "-b:v", "0",
            "-auto-alt-ref", "0", path("alpha.webm"),
        ])
        // Stored 640×360, shown rotated 90° (360×640).
        try await ff([
            "-display_rotation:v:0", "90", "-i", path("normal.mp4"), "-c", "copy", "-t", "1", path("rotated.mp4"),
        ])
        // Already small: compressing it at Highest must keep the original.
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=30:duration=2", "-c:v", "libx264", "-crf", "45",
            path("tiny.mp4"),
        ])
        // Long enough to cancel mid-encode.
        // A 30 s talk with sound throughout: long enough that cutting the sound short shows.
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=10:duration=30", "-f", "lavfi", "-i",
            "sine=f=330:d=30", "-c:v", "libx264", "-crf", "30", "-c:a", "aac", "-b:a", "96k", path("talk.mp4"),
        ])
        try await ff([
            "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=30", "-c:v", "libx264", "-preset",
            "ultrafast",
            path("long.mp4"),
        ])
        return dir
    }
}

@Suite("Video pipeline", .serialized, .enabled(if: videoToolsInstalled, "needs ffmpeg and ffprobe"))
struct VideoPipelineTests {
    let dir = TempDirectory("VideoPipeline")
    var bin: URL { dir.url.appending(path: ".trash") }

    /// Copies a fixture into this test's folder, so outputs land next to it.
    func clip(_ name: String) async throws -> URL {
        let source = try await VideoFixtures.shared.value.url(name)
        let copy = dir.file(name)
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }

    func probe(_ url: URL) async throws -> VideoInfo {
        try await VideoProbe.probe(url, ffprobe: videoTools.ffprobe!, runner: ProcessRunner())
    }

    func run(
        _ input: URL, _ video: VideoSettings = VideoSettings(), encoding: VideoEncodingOptions = VideoEncodingOptions(),
        output: OutputPolicy = OutputPolicy()
    ) async -> JobOutcome {
        await compress(JobRequest(input: input, video: video, output: output, videoEncoding: encoding), trashBin: bin)
    }

    // MARK: Formats

    @Test func compressesMP4InPlace() async throws {
        let input = try await clip("normal.mp4")
        let outcome = await run(input)
        let result = try #require(outcome.result, "\(outcome)")
        #expect(result.output.lastPathComponent == "normal_compressed.mp4")
        #expect(result.outputBytes < result.inputBytes)
        let info = try await probe(result.output)
        #expect(info.videoCodec == "h264")
        #expect(info.codedSize == PixelSize(width: 640, height: 360))
        #expect(info.audioCodecs == ["aac"])
        #expect(abs(info.duration - 2) < 0.2)
    }

    @Test(arguments: [
        (VideoFormatChoice.webm, "webm", "vp9", "opus"), (.mov, "mov", "h264", "aac"), (.mp4, "mp4", "h264", "aac"),
    ])
    func convertsFormats(format: VideoFormatChoice, ext: String, video: String, audio: String) async throws {
        let input = try await clip("normal.mp4")
        let result = try #require(await run(input, VideoSettings(format: format)).result)
        #expect(result.output.pathExtension == ext)
        let info = try await probe(result.output)
        #expect(info.videoCodec == video)
        #expect(info.audioCodecs == [audio])
    }

    /// Stage 2 acceptance: every kind of test clip converts to every container.
    @Test(arguments: ["normal.mp4", "alpha.mov", "twoaudio.mov", "odd.mkv"], [VideoFormatChoice.mp4, .webm, .mov])
    func everyClipToEveryFormat(name: String, format: VideoFormatChoice) async throws {
        let input = try await clip(name)
        let outcome = await run(input, VideoSettings(format: format, preserveTransparency: true))
        let result = try #require(outcome.result, "\(name) → \(format): \(outcome)")
        let info = try await probe(result.output)
        #expect(result.output.pathExtension == format.rawValue)
        #expect(info.codedSize.width % 2 == 0 && info.codedSize.height % 2 == 0)
        if name == "twoaudio.mov" { #expect(info.audioCodecs.count == 2) }
        if name == "alpha.mov", format != .mp4 { #expect(info.hasAlpha, "\(format) should keep alpha") }
    }

    @Test(arguments: [true, false])
    func encodesHEVC(hardware: Bool) async throws {
        let input = try await clip("normal.mp4")
        let options = VideoEncodingOptions(codec: .hevc, hardwareAcceleration: hardware)
        let result = try #require(await run(input, encoding: options).result)
        #expect(try await probe(result.output).videoCodec == "hevc")
    }

    @Test func softwareH264() async throws {
        let input = try await clip("normal.mp4")
        let result = try #require(await run(input, encoding: VideoEncodingOptions(hardwareAcceleration: false)).result)
        #expect(try await probe(result.output).videoCodec == "h264")
    }

    @Test func oddSizeBecomesEven() async throws {
        let input = try await clip("odd.mkv")
        let result = try #require(await run(input).result)
        #expect(result.output.pathExtension == "mkv")
        #expect(try await probe(result.output).codedSize == PixelSize(width: 320, height: 240))
    }

    @Test func keepsEveryAudioTrack() async throws {
        let input = try await clip("twoaudio.mov")
        let result = try #require(await run(input, VideoSettings(format: .mp4)).result)
        #expect(try await probe(result.output).audioCodecs == ["aac", "aac"])
    }

    @Test func transcodesAudioTheContainerCannotHold() async throws {
        let input = try await clip("pcm.mov")
        let result = try #require(await run(input, VideoSettings(format: .mp4)).result)
        #expect(try await probe(result.output).audioCodecs == ["aac"])
    }

    @Test func removesAudio() async throws {
        let input = try await clip("twoaudio.mov")
        let result = try #require(await run(input, VideoSettings(removeAudio: true)).result)
        #expect(try await probe(result.output).audioCodecs.isEmpty)
    }

    // MARK: Transparency

    @Test func webmKeepsAlpha() async throws {
        let input = try await clip("alpha.webm")
        let result = try #require(await run(input, VideoSettings(quality: .good)).result)
        #expect(try await probe(result.output).hasAlpha)
    }

    @Test func movKeepsAlphaWhenAsked() async throws {
        let input = try await clip("alpha.mov")
        let result = try #require(await run(input, VideoSettings(preserveTransparency: true)).result)
        let info = try await probe(result.output)
        #expect(info.videoCodec == "hevc")
        #expect(info.hasAlpha, "AVFoundation should report the HEVC alpha layer")
    }

    @Test func movDropsAlphaByDefault() async throws {
        let input = try await clip("alpha.mov")
        let result = try #require(await run(input).result)
        #expect(try await !probe(result.output).hasAlpha)
    }

    // MARK: Size and frame rate

    @Test func resizesAndNamesWithPresetLabel() async throws {
        let input = try await clip("normal.mp4")
        let output = OutputPolicy(fileNameFormat: "-{quality}-{resolution}")
        let result = try #require(
            await run(input, VideoSettings(quality: .good, resolution: .maxLongEdge(320)), output: output).result)
        #expect(result.pixelSize == PixelSize(width: 320, height: 180))
        #expect(result.output.lastPathComponent == "normal-Good-320x180.mp4")
    }

    @Test func presetNeverUpscalesAndNamesThePreset() async throws {
        let input = try await clip("normal.mp4")
        let output = OutputPolicy(fileNameFormat: "-{quality}-{resolution}")
        let result = try #require(
            await run(input, VideoSettings(quality: .good, resolution: .hd), output: output).result)
        #expect(result.pixelSize == PixelSize(width: 640, height: 360))
        #expect(result.output.lastPathComponent == "normal-Good-HD.mp4")
    }

    @Test func appliesRotation() async throws {
        let input = try await clip("rotated.mp4")
        let before = try await probe(input)
        #expect(before.displaySize == PixelSize(width: 360, height: 640))
        let result = try #require(await run(input).result)
        let after = try await probe(result.output)
        #expect(after.codedSize == PixelSize(width: 360, height: 640))
        #expect(after.rotation == 0)
    }

    @Test func capsFrameRate() async throws {
        let input = try await clip("normal.mp4")
        let result = try #require(await run(input, encoding: VideoEncodingOptions(maxFPS: 15)).result)
        #expect(abs((try await probe(result.output).fps ?? 0) - 15) < 0.1)
    }

    // MARK: Audio from video (SPEC §7 for MP3)

    /// `ffprobe` fields of the output's streams of one type, one line per stream.
    func streams(_ url: URL, _ type: String, _ entries: String) async throws -> [String] {
        let result = try await ProcessRunner().run(
            videoTools.ffprobe!,
            arguments: [
                "-v", "error", "-select_streams", type, "-show_entries", entries, "-of", "csv=p=0", url.path,
            ])
        return result.stdoutString.split(whereSeparator: \.isNewline).map(String.init)
    }

    @Test func extractsMP3() async throws {
        let input = try await clip("normal.mp4")
        let result = try #require(await run(input, VideoSettings(format: .mp3)).result)
        #expect(result.output.lastPathComponent == "normal_compressed.mp3")
        #expect(result.pixelSize == nil)
        #expect(try await streams(result.output, "a", "stream=codec_name,channels") == ["mp3,2"])
        // A frame from the video as square cover art.
        #expect(
            try await streams(result.output, "v", "stream=codec_name,width,height:stream_disposition=attached_pic")
                == ["mjpeg,600,600,1"])
    }

    @Test func extractsSpeechForMessengers() async throws {
        let input = try await clip("normal.mp4")
        let m4a = try #require(await run(input, VideoSettings(format: .m4a, audioProfile: .speech)).result)
        #expect(m4a.output.lastPathComponent == "normal_compressed.m4a")
        // ffprobe prints fields in its own order: codec, sample rate, channels.
        #expect(try await streams(m4a.output, "a", "stream=codec_name,sample_rate,channels") == ["aac,48000,1"])
        #expect(try await streams(m4a.output, "v", "stream_disposition=attached_pic") == ["1"])
        let title = try await ProcessRunner().run(
            videoTools.ffprobe!,
            arguments: ["-v", "error", "-show_entries", "format_tags=title", "-of", "csv=p=0", m4a.output.path])
        #expect(title.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "normal")
    }

    /// Regression: a 67-minute video gave 0.02 s of sound when the cover frame was taken in the same
    /// ffmpeg run. Every format must keep the whole talk, with cover art where the format holds it.
    @Test(arguments: [VideoFormatChoice.m4a, .mp3, .opus])
    func keepsTheWholeSound(format: VideoFormatChoice) async throws {
        let input = try await clip("talk.mp4")
        let outcome = await run(input, VideoSettings(format: format, audioProfile: .speech))
        let result = try #require(outcome.result, "\(outcome)")
        let duration = try #require(
            try await VideoEngine.duration(of: result.output, ffprobe: videoTools.ffprobe!, runner: ProcessRunner()))
        #expect(duration > 29, "\(format): \(duration) s of 30 s")
        let pictures = try await streams(result.output, "v", "stream_disposition=attached_pic")
        #expect(pictures == (format == .opus ? [] : ["1"]))
    }

    @Test func opusSpeechIsMono() async throws {
        let input = try await clip("normal.mp4")
        let opus = try #require(await run(input, VideoSettings(format: .opus, audioProfile: .speech)).result)
        #expect(try await streams(opus.output, "a", "stream=codec_name,channels") == ["opus,1"])
        #expect(try await streams(opus.output, "v", "stream=codec_name").isEmpty)
    }

    @Test func mp3WithoutAudioFails() async throws {
        let input = try await clip("noaudio.mp4")
        guard case .failed(_, let message) = await run(input, VideoSettings(format: .mp3)) else {
            Issue.record("expected failure")
            return
        }
        #expect(message.contains("no audio"))
        #expect(dir.contents() == ["noaudio.mp4"])
    }

    // MARK: Rules, progress, cancellation

    /// Regression: an already-compressed video (low bitrate for its size) must still shrink at the
    /// default and lower levels, not come out larger and be kept (a 1.5 Mbit/s 1080p download did at
    /// High). Highest may keep a clip this short: the VBV buffer alone adds about a second of bitrate.
    @Test(arguments: [QualityLevel.high, .good])
    func alreadyCompressedVideoStillShrinks(quality: QualityLevel) async throws {
        let input = try await clip("tiny.mp4")  // x264 CRF 45
        let outcome = await run(input, VideoSettings(quality: quality))
        let result = try #require(outcome.result, "\(quality): \(outcome)")
        #expect(result.outputBytes < result.inputBytes)
    }

    @Test func progressRisesToOne() async throws {
        final class Values: @unchecked Sendable {
            let lock = NSLock()
            var all: [Double] = []
        }
        let values = Values()
        let input = try await clip("normal.mp4")
        let outcome = await makePipeline(trashBin: bin).process(JobRequest(input: input)) { value in
            values.lock.withLock { values.all.append(value) }
        }
        #expect(outcome.result != nil)
        let seen = values.lock.withLock { values.all }
        #expect(seen == seen.sorted(), "progress never goes back: \(seen)")
        #expect(seen.last == 1)
        #expect(seen.count >= 3)
    }

    @Test func cancellationStopsFFmpegAndLeavesNothing() async throws {
        let input = try await clip("long.mp4")
        let options = VideoEncodingOptions(codec: .hevc, hardwareAcceleration: false)  // slow on purpose
        let task = Task { await run(input, encoding: options) }
        try await Task.sleep(for: .seconds(1.5))
        let started = ContinuousClock.now
        task.cancel()
        #expect(await task.value == .cancelled(input: input))
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(dir.contents() == ["long.mp4"])
        // Only this test process's children, matched by the unique input path.
        let leftovers = try await ProcessRunner().run(
            URL(filePath: "/usr/bin/pgrep"),
            arguments: ["-P", String(ProcessInfo.processInfo.processIdentifier), "-f", input.path])
        #expect(leftovers.stdoutString.isEmpty, "ffmpeg still running: \(leftovers.stdoutString)")
    }
}
