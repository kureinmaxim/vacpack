import AVFoundation
import CoreMedia
import Foundation

/// Facts about an input video from ffprobe (and AVFoundation for HEVC alpha).
struct VideoInfo: Sendable, Equatable {
    var duration: Double
    var codedSize: PixelSize
    /// Display rotation in degrees (from the display matrix); ffmpeg applies it when encoding.
    var rotation: Int
    var fps: Double?
    var pixelFormat: String?
    var videoCodec: String
    var hasAlpha: Bool
    /// Decoder to force for VP8/VP9 with an alpha layer: only libvpx reads it, the native one drops it.
    var alphaDecoder: String?
    /// Codec of each audio stream, in stream order.
    var audioCodecs: [String]

    /// Size as shown to the viewer, with rotation applied.
    var displaySize: PixelSize {
        abs(rotation) % 180 == 90 ? PixelSize(width: codedSize.height, height: codedSize.width) : codedSize
    }

    var bitDepth: Int {
        guard let format = pixelFormat else { return 8 }
        if format.contains("12") { return 12 }
        if format.contains("10") || format == "p010le" { return 10 }
        return 8
    }
}

enum VideoError: Error, CustomStringConvertible, Equatable {
    case toolMissing(Tool)
    case unreadable(String)
    case noVideoStream
    case noAudioTrack
    case ffmpegFailed(String)
    case transparencyNeedsAppleSilicon

    var description: String {
        switch self {
        case .toolMissing(let tool): "\(tool.rawValue) is not installed"
        case .unreadable(let reason): "Cannot read the video: \(reason)"
        case .noVideoStream: "The file has no video stream"
        case .noAudioTrack: "The video has no audio track to extract"
        case .ffmpegFailed(let message): "ffmpeg failed: \(message)"
        case .transparencyNeedsAppleSilicon: "Transparent MOV output needs Apple Silicon"
        }
    }
}

enum VideoProbe {
    static func probe(_ url: URL, ffprobe: URL, runner: ProcessRunner) async throws -> VideoInfo {
        let result = try await runner.run(
            ffprobe,
            arguments: ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path],
            timeout: .seconds(60))
        guard result.exitCode == 0 else { throw VideoError.unreadable(lastLine(result.stderrString)) }
        var info = try parse(result.stdout)
        if !info.hasAlpha, info.videoCodec == "hevc", await hevcHasAlpha(url) { info.hasAlpha = true }
        return info
    }

    /// Builds `VideoInfo` from `ffprobe -print_format json -show_format -show_streams` output.
    static func parse(_ json: Data) throws -> VideoInfo {
        let output: FFProbeOutput
        do {
            output = try JSONDecoder().decode(FFProbeOutput.self, from: json)
        } catch {
            throw VideoError.unreadable("unexpected ffprobe output")
        }
        // Skip cover art: attached pictures are reported as video streams.
        guard
            let video = output.streams.first(where: {
                $0.codec_type == "video" && ($0.disposition?["attached_pic"] ?? 0) == 0
            }),
            let width = video.width, let height = video.height
        else { throw VideoError.noVideoStream }

        let tags = Dictionary(uniqueKeysWithValues: (video.tags ?? [:]).map { ($0.key.lowercased(), $0.value) })
        let alphaMode = tags["alpha_mode"] == "1"
        let rotation = video.side_data_list?.compactMap(\.rotation).first.map { Int($0.rounded()) } ?? 0
        let pixelFormat = video.pix_fmt
        let alphaFormats = ["yuva", "rgba", "bgra", "argb", "abgr", "gbrap", "ya8", "ya16"]
        let duration = Double(output.format.duration ?? "") ?? Double(video.duration ?? "") ?? 0

        return VideoInfo(
            duration: duration,
            codedSize: PixelSize(width: width, height: height),
            rotation: rotation,
            fps: parseRate(video.avg_frame_rate) ?? parseRate(video.r_frame_rate),
            pixelFormat: pixelFormat,
            videoCodec: video.codec_name ?? "unknown",
            hasAlpha: alphaMode || alphaFormats.contains { pixelFormat?.hasPrefix($0) ?? false },
            alphaDecoder: alphaMode ? ["vp9": "libvpx-vp9", "vp8": "libvpx"][video.codec_name ?? ""] : nil,
            audioCodecs: output.streams.filter { $0.codec_type == "audio" }.map { $0.codec_name ?? "unknown" })
    }

    /// "30000/1001" → 29.97; "0/0" → nil.
    static func parseRate(_ rate: String?) -> Double? {
        guard let rate else { return nil }
        let parts = rate.split(separator: "/").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0, parts[0] > 0 else { return nil }
        return parts[0] / parts[1]
    }

    /// ffprobe cannot see HEVC's alpha layer; AVFoundation reports it in the format description.
    static func hevcHasAlpha(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let descriptions = try? await track.load(.formatDescriptions)
        else { return false }
        return descriptions.contains { description in
            let value = CMFormatDescriptionGetExtension(
                description, extensionKey: kCMFormatDescriptionExtension_ContainsAlphaChannel)
            return (value as? Bool) == true || (value as? NSNumber)?.boolValue == true
        }
    }

    static func lastLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).last.map(String.init) ?? text
    }
}

/// The parts of ffprobe's JSON we use.
private struct FFProbeOutput: Decodable {
    struct Stream: Decodable {
        struct SideData: Decodable {
            let rotation: Double?
        }

        let codec_type: String?
        let codec_name: String?
        let width: Int?
        let height: Int?
        let pix_fmt: String?
        let avg_frame_rate: String?
        let r_frame_rate: String?
        let duration: String?
        let tags: [String: String]?
        let side_data_list: [SideData]?
        let disposition: [String: Int]?
    }

    struct Format: Decodable {
        let duration: String?
    }

    let streams: [Stream]
    let format: Format
}
