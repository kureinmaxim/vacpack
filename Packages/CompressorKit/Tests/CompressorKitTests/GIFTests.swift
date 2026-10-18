import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CompressorKit

let gifToolsInstalled = videoToolsInstalled && ToolLocator().locate(.gifski) != nil

enum TestGIF {
    /// Writes an animated GIF with ImageIO: one frame per delay, flat color blocks that change per
    /// frame, optionally with the left quarter transparent.
    @discardableResult
    static func write(to url: URL, width: Int = 160, height: Int = 120, delays: [Double], alpha: Bool = false) -> URL {
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, delays.count, nil)!
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (index, delay) in delays.enumerated() {
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: TestImage.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1))
            context.fill(CGRect(x: (index * 10) % width, y: height / 3, width: 20, height: 20))
            if alpha { context.clear(CGRect(x: 0, y: 0, width: width / 4, height: height)) }
            let frame: [CFString: Any] = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]]
            CGImageDestinationAddImage(destination, context.makeImage()!, frame as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return url
    }

    static func frameCount(_ url: URL) -> Int {
        CGImageSourceCreateWithURL(url as CFURL, nil).map(CGImageSourceGetCount) ?? 0
    }

    static func firstFrame(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}

@Suite("GIF rules")
struct GIFRuleTests {
    let source = PixelSize(width: 640, height: 360)

    @Test(arguments: [
        (GIFDimension.same, PixelSize(width: 640, height: 360)),
        (.percentage(75), PixelSize(width: 480, height: 270)),
        (.percentage(25), PixelSize(width: 160, height: 90)),
        (.maxWidth(320), PixelSize(width: 320, height: 180)),
        (.maxWidth(2000), PixelSize(width: 640, height: 360)),  // never upscale
    ])
    func sizes(dimension: GIFDimension, expected: PixelSize) {
        #expect(GIFSizeMath.target(for: source, dimension: dimension) == expected)
    }

    @Test func videoFrameRateIsClampedAndNeverRaised() {
        let video = AnimationSource(size: source, duration: 2, fps: 24, alphaDecoder: nil)
        #expect(GIFSizeMath.fps(for: video, isVideo: true, settings: GIFSettings(fps: 15)) == 15)
        #expect(GIFSizeMath.fps(for: video, isVideo: true, settings: GIFSettings(fps: 30)) == 24)
        #expect(GIFSizeMath.fps(for: video, isVideo: true, settings: GIFSettings(fps: 5)) == 10)
        let fast = AnimationSource(size: source, duration: 2, fps: 120, alphaDecoder: nil)
        #expect(GIFSizeMath.fps(for: fast, isVideo: true, settings: GIFSettings(fps: 99)) == 50)
    }

    @Test func gifKeepsItsRateUpToFifty() {
        let gif = AnimationSource(size: source, duration: 1, fps: 12.5, alphaDecoder: nil)
        #expect(GIFSizeMath.fps(for: gif, isVideo: false, settings: GIFSettings(fps: 10)) == 12.5)
        let fast = AnimationSource(size: source, duration: 1, fps: 100, alphaDecoder: nil)
        #expect(GIFSizeMath.fps(for: fast, isVideo: false, settings: GIFSettings()) == 50)
    }

    @Test func readsGIFTiming() throws {
        let dir = TempDirectory()
        let url = TestGIF.write(to: dir.file("a.gif"), delays: [0.5, 0.1, 0.1, 0.1, 0.2])
        let source = try GIFEngine.gifSource(url)
        #expect(source.size == PixelSize(width: 160, height: 120))
        #expect(abs(source.duration - 1.0) < 0.001)
        #expect(source.fps == 10, "the shortest delay sets the rate, so every frame is shown")
    }

    @Test func zeroDelaysCountAsBrowsersShowThem() throws {
        let dir = TempDirectory()
        let url = TestGIF.write(to: dir.file("a.gif"), delays: [0, 0, 0, 0])
        #expect(abs(try GIFEngine.gifSource(url).duration - 0.4) < 0.001)
    }

    @Test func gifskiProgressLines() {
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var values: [Double] = []
        }
        let box = Box()
        let progress = GifskiProgress { value in box.lock.withLock { box.values.append(value) } }
        for line in ["Frame 1 / 4  #___", "noise", "Frame 1 / 4", "Frame 2 / 4", "547KB GIF; Frame 4 / 4  ####"] {
            progress.handle(line)
        }
        #expect(box.lock.withLock { box.values } == [0.25, 0.5, 1])
    }

    @Test func gifskiGetsExplicitSize() {
        let args = GIFEngine.gifskiArguments(
            quality: .good, fps: 12.5, size: PixelSize(width: 960, height: 540), output: URL(filePath: "/o.gif"),
            frames: [URL(filePath: "/f/1.png")])
        #expect(
            args == [
                "--fps", "12.50", "--quality", "80", "--width", "960", "--height", "540", "--output", "/o.gif",
                "/f/1.png",
            ])
    }
}

@Suite("GIF pipeline", .serialized, .enabled(if: gifToolsInstalled, "needs ffmpeg, ffprobe and gifski"))
struct GIFPipelineTests {
    let dir = TempDirectory("GIFPipeline")
    var bin: URL { dir.url.appending(path: ".trash") }

    func clip(_ name: String) async throws -> URL {
        let copy = dir.file(name)
        try FileManager.default.copyItem(at: try await VideoFixtures.shared.value.url(name), to: copy)
        return copy
    }

    func makeClip(_ name: String, size: String, rate: Int, seconds: Int) async throws -> URL {
        let url = dir.file(name)
        _ = try await ProcessRunner().run(
            videoTools.ffmpeg!,
            arguments: [
                "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                "testsrc2=size=\(size):rate=\(rate):duration=\(seconds)", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                url.path,
            ]
        ).checked()
        return url
    }

    func toGIF(_ input: URL, _ gif: GIFSettings = GIFSettings()) async -> JobOutcome {
        await compress(JobRequest(input: input, video: VideoSettings(format: .gif), gif: gif), trashBin: bin)
    }

    // MARK: Video → GIF

    @Test func convertsVideoWithFrameRateAndSize() async throws {
        let input = try await clip("normal.mp4")  // 640×360, 30 fps, 2 s
        let result = try #require(await toGIF(input, GIFSettings(dimension: .percentage(50), fps: 15)).result)
        #expect(result.output.lastPathComponent == "normal_compressed.gif")
        #expect(result.pixelSize == PixelSize(width: 320, height: 180))
        #expect(TestImage.typeIdentifier(result.output) == UTType.gif.identifier)
        #expect(abs(TestGIF.frameCount(result.output) - 30) <= 2, "15 fps × 2 s")
        #expect(abs(try GIFEngine.gifSource(result.output).duration - 2) < 0.2)
    }

    @Test func neverRaisesTheVideoFrameRate() async throws {
        let input = try await makeClip("slow.mp4", size: "320x240", rate: 10, seconds: 2)
        let result = try #require(await toGIF(input, GIFSettings(fps: 30)).result)
        #expect(abs(TestGIF.frameCount(result.output) - 20) <= 2, "10 fps × 2 s")
    }

    @Test func keepsLargeAndTallFramesFullSize() async throws {
        // gifski shrinks to about 800×600 unless told the size.
        let wide = try await makeClip("wide.mp4", size: "960x540", rate: 10, seconds: 1)
        #expect(
            try #require(await toGIF(wide, GIFSettings(fps: 10)).result).pixelSize == PixelSize(width: 960, height: 540)
        )
        let rotated = try await clip("rotated.mp4")  // shown 360×640
        let result = try #require(await toGIF(rotated, GIFSettings(fps: 10)).result)
        #expect(result.pixelSize == PixelSize(width: 360, height: 640))
        let frame = try #require(TestGIF.firstFrame(result.output))
        #expect(frame.width == 360 && frame.height == 640)
    }

    @Test func videoAlphaBecomesGIFTransparency() async throws {
        let input = try await clip("alpha.webm")  // half-transparent everywhere
        let result = try #require(await toGIF(input, GIFSettings(fps: 10)).result)
        let frame = try #require(TestGIF.firstFrame(result.output))
        #expect(frame.alphaInfo != .none && frame.alphaInfo != .noneSkipLast && frame.alphaInfo != .noneSkipFirst)
    }

    @Test func progressRisesToOne() async throws {
        final class Values: @unchecked Sendable {
            let lock = NSLock()
            var all: [Double] = []
        }
        let values = Values()
        let input = try await clip("normal.mp4")
        let request = JobRequest(input: input, video: VideoSettings(format: .gif), gif: GIFSettings(fps: 10))
        let outcome = await makePipeline(trashBin: bin).process(request) { v in
            values.lock.withLock { values.all.append(v) }
        }
        #expect(outcome.result != nil)
        let seen = values.lock.withLock { values.all }
        #expect(seen == seen.sorted(), "never goes back: \(seen)")
        #expect(seen.last == 1)
        #expect(seen.contains { $0 > 0.5 && $0 < 1 }, "gifski phase reports progress: \(seen)")
    }

    @Test func cancellationStopsBothToolsAndLeavesNothing() async throws {
        let input = try await clip("long.mp4")
        // Only our own child processes count: matching command lines system-wide would also find any
        // shell that merely mentions the words. ffmpeg's arguments contain this test's input path.
        let pgrep = URL(filePath: "/usr/bin/pgrep")
        let ownPID = String(ProcessInfo.processInfo.processIdentifier)
        let checks = [("ffmpeg", ["-P", ownPID, "-f", input.path]), ("gifski", ["-P", ownPID, "gifski"])]
        func running() async throws -> [String] {
            var found: [String] = []
            for (name, arguments) in checks
            where try await !ProcessRunner().run(pgrep, arguments: arguments).stdoutString.isEmpty {
                found.append(name)
            }
            return found
        }

        let task = Task { await toGIF(input, GIFSettings(quality: .highest, fps: 50)) }
        try await Task.sleep(for: .seconds(1.5))
        #expect(try await !running().isEmpty, "the check must see the tools while they run")
        task.cancel()
        #expect(await task.value == .cancelled(input: input))
        #expect(dir.contents() == ["long.mp4"])
        #expect(try await running().isEmpty, "still running after cancel")
    }

    // MARK: GIF → GIF

    /// A noisy, dithered GIF from ffmpeg: gifski at Acceptable makes it smaller.
    func noisyGIF() async throws -> URL {
        let url = dir.file("noisy.gif")
        _ = try await ProcessRunner().run(
            videoTools.ffmpeg!,
            arguments: [
                "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
                "testsrc2=size=320x240:rate=10:duration=2,noise=alls=20:allf=t,split[a][b];[a]palettegen=stats_mode=single[p];[b][p]paletteuse=new=1:dither=sierra2_4a",
                url.path,
            ]
        ).checked()
        return url
    }

    @Test func compressesGIFKeepingFramesAndTiming() async throws {
        let input = try await noisyGIF()
        let before = try GIFEngine.gifSource(input)
        let outcome = await compress(JobRequest(input: input, gif: GIFSettings(quality: .acceptable)), trashBin: bin)
        let result = try #require(outcome.result, "\(outcome)")
        #expect(result.output.lastPathComponent == "noisy_compressed.gif")
        #expect(result.outputBytes < result.inputBytes)
        #expect(result.pixelSize == PixelSize(width: 320, height: 240))
        #expect(TestGIF.frameCount(result.output) == TestGIF.frameCount(input))
        #expect(abs(try GIFEngine.gifSource(result.output).duration - before.duration) < 0.15)
    }

    @Test(arguments: [
        (GIFDimension.maxWidth(80), PixelSize(width: 80, height: 60)),
        (.percentage(50), PixelSize(width: 80, height: 60)),
        (.maxWidth(1000), PixelSize(width: 160, height: 120)),
    ])
    func resizesGIF(dimension: GIFDimension, expected: PixelSize) async throws {
        let input = TestGIF.write(to: dir.file("blocks.gif"), delays: Array(repeating: 0.1, count: 8))
        let outcome = await compress(JobRequest(input: input, gif: GIFSettings(dimension: dimension)), trashBin: bin)
        switch outcome {
        case .compressed(let result):
            #expect(result.pixelSize == expected)
            #expect(TestGIF.firstFrame(result.output)?.width == expected.width)
        case .keptOriginal:
            // Same size and not smaller: the original stays (SPEC §8).
            #expect(expected == PixelSize(width: 160, height: 120))
        default:
            Issue.record("unexpected \(outcome)")
        }
    }

    @Test func keepsTransparency() async throws {
        let input = TestGIF.write(to: dir.file("alpha.gif"), delays: Array(repeating: 0.1, count: 6), alpha: true)
        let outcome = await compress(
            JobRequest(input: input, gif: GIFSettings(dimension: .percentage(50))), trashBin: bin)
        let result = try #require(outcome.result, "\(outcome)")
        let frame = try #require(TestGIF.firstFrame(result.output))
        #expect(TestImage.pixel(frame, x: 2, y: frame.height / 2)[3] == 0, "left quarter stays transparent")
        #expect(TestImage.pixel(frame, x: frame.width - 3, y: frame.height / 2)[3] == 255)
    }

    @Test func keepsUnevenFrameTiming() async throws {
        let delays = [0.5, 0.1, 0.1, 0.1, 0.1, 0.5]
        let input = TestGIF.write(to: dir.file("uneven.gif"), delays: delays)
        let outcome = await compress(
            JobRequest(input: input, gif: GIFSettings(dimension: .percentage(50))), trashBin: bin)
        let result = try #require(outcome.result, "\(outcome)")
        #expect(abs(try GIFEngine.gifSource(result.output).duration - delays.reduce(0, +)) < 0.15)
    }

    @Test func gifskiMissingIsAClearError() async throws {
        let input = TestGIF.write(to: dir.file("a.gif"), delays: [0.1, 0.1])
        let pipeline = CompressionPipeline(
            image: ImageEngine(tools: installedImageTools), video: VideoEngine(locator: ToolLocator()),
            gif: GIFEngine(ffmpeg: videoTools.ffmpeg, ffprobe: videoTools.ffprobe, gifski: nil),
            trasher: RecordingTrasher(bin: bin))
        guard case .failed(_, let message) = await pipeline.process(JobRequest(input: input), progress: { _ in }) else {
            Issue.record("expected failure")
            return
        }
        #expect(message == "gifski is not installed")
    }
}
