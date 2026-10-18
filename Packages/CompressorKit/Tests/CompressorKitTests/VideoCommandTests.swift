import Foundation
import Testing

@testable import CompressorKit

/// Rules of the ffmpeg command, checked without running ffmpeg.
@Suite("Video command")
struct VideoCommandTests {
    let input = URL(filePath: "/in/clip.mp4")
    let output = URL(filePath: "/work/encoded.mp4")
    let appleSilicon = VideoCommand.Environment(videoToolboxQuality: true)
    let intel = VideoCommand.Environment(videoToolboxQuality: false)

    func info(
        size: PixelSize = PixelSize(width: 1920, height: 1080), rotation: Int = 0, fps: Double? = 30,
        pixelFormat: String = "yuv420p", codec: String = "h264", alpha: Bool = false, alphaDecoder: String? = nil,
        audio: [String] = ["aac"], bitrate: Int? = nil
    ) -> VideoInfo {
        VideoInfo(
            duration: 10, codedSize: size, rotation: rotation, fps: fps, pixelFormat: pixelFormat, videoCodec: codec,
            hasAlpha: alpha, alphaDecoder: alphaDecoder, audioCodecs: audio, videoBitrate: bitrate)
    }

    let hardware = VideoEncodingOptions(hardwareAcceleration: true)

    func build(
        _ info: VideoInfo, _ settings: VideoSettings = VideoSettings(),
        options: VideoEncodingOptions = VideoEncodingOptions(), input: URL? = nil,
        environment: VideoCommand.Environment? = nil
    ) throws -> VideoCommand {
        try VideoCommand.build(
            input: input ?? self.input, output: output, info: info, settings: settings, options: options,
            environment: environment ?? appleSilicon)
    }

    /// The value after `flag`, or nil.
    func value(_ args: [String], _ flag: String) -> String? {
        args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    // MARK: Output and size

    @Test(arguments: [
        ("mp4", VideoOutput.video(.mp4)), ("MOV", .video(.mov)), ("webm", .video(.webm)), ("mkv", .video(.mkv)),
        ("avi", .video(.mp4)), ("ts", .video(.mp4)), ("flv", .video(.mp4)),
    ])
    func sameFormatPerContainer(ext: String, expected: VideoOutput) {
        #expect(VideoOutput.resolve(.same, inputExtension: ext) == expected)
    }

    @Test(arguments: [
        (VideoResolution.same, PixelSize(width: 1920, height: 1080)),
        (.uhd4K, PixelSize(width: 1920, height: 1080)),  // never upscale
        (.fullHD, PixelSize(width: 1920, height: 1080)),
        (.hd, PixelSize(width: 1280, height: 720)),
        (.maxWidth(1000), PixelSize(width: 1000, height: 562)),  // 562.5 → even
        (.maxLongEdge(640), PixelSize(width: 640, height: 360)),
        (.maxShortEdge(480), PixelSize(width: 852, height: 480)),
    ])
    func sizes(resolution: VideoResolution, expected: PixelSize) {
        #expect(VideoSizeMath.target(display: PixelSize(width: 1920, height: 1080), resolution: resolution) == expected)
    }

    @Test func presetsFitPortraitVideo() {
        // A 1080×1920 phone video stays 1080p, not squeezed into 1080 px height.
        #expect(
            VideoSizeMath.target(display: PixelSize(width: 1080, height: 1920), resolution: .fullHD)
                == PixelSize(width: 1080, height: 1920))
        #expect(
            VideoSizeMath.target(display: PixelSize(width: 1080, height: 1920), resolution: .hd)
                == PixelSize(width: 720, height: 1280))
    }

    @Test func oddSizesBecomeEvenWithScale() throws {
        let command = try build(info(size: PixelSize(width: 321, height: 241)))
        #expect(command.size == PixelSize(width: 320, height: 240))
        #expect(value(command.arguments, "-vf") == "scale=320:240:flags=lanczos")
    }

    @Test func noFiltersWhenNothingChanges() throws {
        #expect(try !build(info()).arguments.contains("-vf"))
    }

    @Test func rotationIsAppliedBeforeSizing() throws {
        // Coded 1920×1080 rotated 90° is shown 1080×1920.
        let command = try build(info(rotation: -90), VideoSettings(resolution: .maxLongEdge(960)))
        #expect(command.size == PixelSize(width: 540, height: 960))
    }

    @Test func fpsIsOnlyLowered() throws {
        let capped = try build(info(fps: 60), options: VideoEncodingOptions(maxFPS: 30))
        #expect(value(capped.arguments, "-vf") == "fps=30")
        let kept = try build(info(fps: 24), options: VideoEncodingOptions(maxFPS: 30))
        #expect(!kept.arguments.contains("-vf"))
        let ntsc = try build(info(fps: 30_000.0 / 1001), options: VideoEncodingOptions(maxFPS: 30))
        #expect(!ntsc.arguments.contains("-vf"), "29.97 is not above 30")
    }

    // MARK: Encoders

    @Test func hardwareH264OnAppleSiliconWhenAsked() throws {
        let args = try build(info(), options: hardware).arguments
        #expect(value(args, "-c:v") == "h264_videotoolbox")
        #expect(value(args, "-q:v") == "58")
        #expect(value(args, "-pix_fmt") == "yuv420p")
    }

    @Test func softwareByDefaultAndOnIntel() throws {
        let byDefault = try build(info()).arguments
        #expect(value(byDefault, "-c:v") == "libx264")
        #expect(value(byDefault, "-crf") == "21")
        let intel = try build(info(), options: hardware, environment: intel).arguments
        #expect(value(intel, "-c:v") == "libx264")
    }

    @Test func hevcGetsAppleTagAndKeepsTenBit() throws {
        let args = try build(
            info(pixelFormat: "yuv420p10le"), options: VideoEncodingOptions(codec: .hevc, hardwareAcceleration: true)
        ).arguments
        #expect(value(args, "-c:v") == "hevc_videotoolbox")
        #expect(value(args, "-tag:v") == "hvc1")
        #expect(value(args, "-pix_fmt") == "p010le")
        let software = try build(
            info(pixelFormat: "yuv420p10le"), options: VideoEncodingOptions(codec: .hevc, hardwareAcceleration: false)
        ).arguments
        #expect(value(software, "-c:v") == "libx265")
        #expect(value(software, "-pix_fmt") == "yuv420p10le")
    }

    @Test func webmUsesVP9AndOpus() throws {
        let args = try build(info(), VideoSettings(format: .webm)).arguments
        #expect(value(args, "-c:v") == "libvpx-vp9")
        #expect(value(args, "-b:v") == "0")
        #expect(value(args, "-c:a:0") == "libopus")
        #expect(args.last == output.path)
    }

    @Test func qualityLevelsMapToEncoderValues() throws {
        let crf = try QualityLevel.allCases.map {
            Int(value(try build(info(), VideoSettings(quality: $0)).arguments, "-crf")!)!
        }
        #expect(crf == crf.sorted(), "lower quality, higher CRF")
        let videoToolbox = try QualityLevel.allCases.map {
            Int(value(try build(info(), VideoSettings(quality: $0), options: hardware).arguments, "-q:v")!)!
        }
        #expect(videoToolbox == videoToolbox.sorted(by: >), "higher quality, higher VideoToolbox value")
    }

    // MARK: Rate cap from the source bitrate

    @Test func softwareEncodersAreCappedBelowTheSource() throws {
        // A 1.55 Mbit/s 1080p download at High may use at most 75% of it.
        let args = try build(info(bitrate: 1_550_000)).arguments
        #expect(value(args, "-crf") == "21")
        #expect(value(args, "-maxrate") == "1162k")
        #expect(value(args, "-bufsize") == "1162k")
        let hevc = try build(info(bitrate: 1_550_000), options: VideoEncodingOptions(codec: .hevc)).arguments
        #expect(value(hevc, "-maxrate") == "1162k")
    }

    @Test func capShrinksWithQuality() throws {
        let caps = try QualityLevel.allCases.map {
            Int(
                value(try build(info(bitrate: 10_000_000), VideoSettings(quality: $0)).arguments, "-maxrate")!
                    .dropLast())!
        }
        #expect(caps == [9000, 7500, 6000, 4500, 3200])
    }

    @Test func noCapWithoutAKnownBitrate() throws {
        #expect(try !build(info()).arguments.contains("-maxrate"))
        #expect(try value(build(info(), options: hardware).arguments, "-q:v") == "58")
    }

    @Test func videoToolboxGetsAnAverageBitrate() throws {
        // Low-bitrate source: the cap wins.
        let low = try build(info(bitrate: 1_550_000), options: hardware).arguments
        #expect(value(low, "-b:v") == "1162k")
        #expect(!low.contains("-q:v"))
        // 50 Mbit/s camera footage: the resolution ceiling wins (1920×1080×30×0.10).
        let camera = try build(info(bitrate: 50_000_000), options: hardware).arguments
        #expect(value(camera, "-b:v") == "6220k")
        // HEVC needs less.
        let hevc = try build(
            info(bitrate: 50_000_000), options: VideoEncodingOptions(codec: .hevc, hardwareAcceleration: true)
        ).arguments
        #expect(value(hevc, "-b:v") == "4043k")
    }

    @Test func webmUsesConstrainedQuality() throws {
        let args = try build(info(bitrate: 1_550_000), VideoSettings(format: .webm)).arguments
        #expect(value(args, "-crf") == "30")
        #expect(value(args, "-b:v") == "1162k")
    }

    // MARK: Alpha

    @Test func webmKeepsAlphaAndForcesLibvpxDecoder() throws {
        let alpha = info(codec: "vp9", alpha: true, alphaDecoder: "libvpx-vp9", audio: [])
        let args = try build(alpha, VideoSettings(format: .webm), input: URL(filePath: "/in/a.webm")).arguments
        #expect(Array(args.prefix(args.firstIndex(of: "-i")!)).suffix(2) == ["-c:v", "libvpx-vp9"])
        #expect(value(args, "-pix_fmt") == "yuva420p")
        #expect(args.contains("-an"))
    }

    @Test func movKeepsAlphaOnlyWhenAsked() throws {
        let alpha = info(codec: "prores", alpha: true)
        let mov = URL(filePath: "/in/a.mov")
        let kept = try build(alpha, VideoSettings(preserveTransparency: true), input: mov).arguments
        #expect(value(kept, "-c:v") == "hevc_videotoolbox")
        #expect(value(kept, "-alpha_quality") == "0.75")
        #expect(value(kept, "-pix_fmt") == "bgra")
        let dropped = try build(alpha, VideoSettings(), input: mov).arguments
        #expect(value(dropped, "-c:v") == "libx264")
        // MP4 cannot carry alpha even when asked.
        let mp4 = try build(alpha, VideoSettings(format: .mp4, preserveTransparency: true), input: mov).arguments
        #expect(value(mp4, "-c:v") == "libx264")
    }

    // MARK: Audio

    @Test func audioIsCopiedWhenTheContainerAllowsIt() throws {
        let args = try build(info(audio: ["aac", "aac"])).arguments
        #expect(value(args, "-c:a:0") == "copy")
        #expect(value(args, "-c:a:1") == "copy")
        #expect(value(args, "-map") == "0:V:0")
        #expect(args.contains("0:a?"))
    }

    @Test func incompatibleAudioIsTranscodedPerStream() throws {
        let args = try build(info(audio: ["pcm_s16le", "aac"]), VideoSettings(format: .mp4)).arguments
        #expect(value(args, "-c:a:0") == "aac")
        #expect(value(args, "-c:a:1") == "copy")
        let mov = try build(info(audio: ["pcm_s16le"]), VideoSettings(format: .mov)).arguments
        #expect(value(mov, "-c:a:0") == "copy", "MOV keeps PCM")
    }

    @Test func removeAudioDropsAllAudio() throws {
        let args = try build(info(audio: ["aac", "aac"]), VideoSettings(removeAudio: true)).arguments
        #expect(args.contains("-an"))
        #expect(!args.contains("0:a?"))
        #expect(!args.contains("-c:a:0"))
    }

    @Test func mp3ExtractsFirstAudioTrack() throws {
        let command = try build(info(audio: ["aac", "ac3"]), VideoSettings(format: .mp3))
        #expect(command.output == .mp3)
        #expect(command.size == nil)
        #expect(value(command.arguments, "-c:a") == "libmp3lame")
        #expect(value(command.arguments, "-q:a") == "0")
        #expect(value(command.arguments, "-map") == "0:a:0")
    }

    @Test func mp3WithoutAudioFails() {
        #expect(throws: VideoError.noAudioTrack) { try build(info(audio: []), VideoSettings(format: .mp3)) }
    }

    @Test func threadsLimitIsPassed() throws {
        let args = try build(info(), options: VideoEncodingOptions(threads: 2)).arguments
        #expect(value(args, "-threads") == "2")
    }
}

@Suite("Video probe and progress")
struct VideoProbeParsingTests {
    @Test func parsesStreamsRotationAlphaAndAudio() throws {
        let json = """
            {"streams":[
              {"codec_type":"video","codec_name":"mjpeg","width":300,"height":300,"disposition":{"attached_pic":1}},
              {"codec_type":"video","codec_name":"vp9","width":1280,"height":720,"pix_fmt":"yuv420p",
               "avg_frame_rate":"30000/1001","tags":{"ALPHA_MODE":"1"},
               "side_data_list":[{"side_data_type":"Display Matrix","rotation":-90}]},
              {"codec_type":"audio","codec_name":"opus"},{"codec_type":"audio","codec_name":"vorbis"}],
             "format":{"duration":"12.5"}}
            """
        let info = try VideoProbe.parse(Data(json.utf8))
        #expect(info.videoCodec == "vp9", "cover art is skipped")
        #expect(info.codedSize == PixelSize(width: 1280, height: 720))
        #expect(info.displaySize == PixelSize(width: 720, height: 1280))
        #expect(info.hasAlpha)
        #expect(info.alphaDecoder == "libvpx-vp9")
        #expect(info.audioCodecs == ["opus", "vorbis"])
        #expect(abs((info.fps ?? 0) - 29.97) < 0.01)
        #expect(info.duration == 12.5)
    }

    @Test func readsVideoBitrate() throws {
        let mp4 = """
            {"streams":[{"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"bit_rate":"1551236"},
              {"codec_type":"audio","codec_name":"aac","bit_rate":"128000"}],"format":{"duration":"10","bit_rate":"1686833"}}
            """
        #expect(try VideoProbe.parse(Data(mp4.utf8)).videoBitrate == 1_551_236)
        // Matroska: only the file's rate; audio is subtracted (128 kbit/s assumed when unknown).
        let mkv = """
            {"streams":[{"codec_type":"video","codec_name":"vp9","width":640,"height":360},
              {"codec_type":"audio","codec_name":"opus"}],"format":{"duration":"10","bit_rate":"1128000"}}
            """
        #expect(try VideoProbe.parse(Data(mkv.utf8)).videoBitrate == 1_000_000)
        let unknown = #"{"streams":[{"codec_type":"video","codec_name":"h264","width":2,"height":2}],"format":{}}"#
        #expect(try VideoProbe.parse(Data(unknown.utf8)).videoBitrate == nil)
    }

    @Test func alphaFromPixelFormatAndBitDepth() throws {
        let json = """
            {"streams":[{"codec_type":"video","codec_name":"prores","width":64,"height":64,"pix_fmt":"yuva444p12le"}],
             "format":{"duration":"1"}}
            """
        let info = try VideoProbe.parse(Data(json.utf8))
        #expect(info.hasAlpha)
        #expect(info.alphaDecoder == nil)
        #expect(info.bitDepth == 12)
    }

    @Test func noVideoStream() {
        let json = #"{"streams":[{"codec_type":"audio","codec_name":"aac"}],"format":{}}"#
        #expect(throws: VideoError.noVideoStream) { try VideoProbe.parse(Data(json.utf8)) }
    }

    @Test func progressIsMonotonicAndCapped() {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var values: [Double] = []
        }
        let box = Box()
        let progress = FFmpegProgress(duration: 10) { value in box.lock.withLock { box.values.append(value) } }
        for line in [
            "frame=1", "out_time_us=1000000", "out_time_us=500000", "out_time_us=1001000", "out_time_us=5000000",
            "out_time_us=20000000", "progress=end",
        ] {
            progress.handle(line)
        }
        let values = box.lock.withLock { box.values }
        #expect(values == [0.1, 0.5, 0.99])
    }
}
