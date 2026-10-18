import CoreGraphics
import Foundation
import ImageIO

/// External encoders the image engine uses. A missing tool fails only the formats that need it.
public struct ImageTools: Sendable {
    public var pngquant: URL?
    public var cwebp: URL?
    public var avifenc: URL?

    public init(pngquant: URL? = nil, cwebp: URL? = nil, avifenc: URL? = nil) {
        self.pngquant = pngquant
        self.cwebp = cwebp
        self.avifenc = avifenc
    }

    public init(locator: ToolLocator) {
        self.init(
            pngquant: locator.locate(.pngquant)?.url, cwebp: locator.locate(.cwebp)?.url,
            avifenc: locator.locate(.avifenc)?.url)
    }
}

enum ImageEncodeError: Error, CustomStringConvertible {
    case writeFailed(String)
    case toolMissing(Tool)
    case toolFailed(Tool, String)

    var description: String {
        switch self {
        case .writeFailed(let format): "Could not write \(format) image"
        case .toolMissing(let tool): "\(tool.rawValue) is not installed"
        case .toolFailed(let tool, let message): "\(tool.rawValue) failed: \(message)"
        }
    }
}

/// Writes a prepared bitmap in one concrete format.
struct ImageEncoder {
    let tools: ImageTools
    let runner: ProcessRunner

    struct Options {
        var quality: QualityLevel
        /// Written for JPEG/PNG when the input had it (SPEC §3).
        var dpi: (width: Double, height: Double)?
        /// Keep the bitmap's embedded color profile; otherwise drop profiles that only restate sRGB.
        var keepProfile: Bool
    }

    /// Encodes `image` into `directory` and returns the file URL.
    func encode(_ image: CGImage, as format: ConcreteImageFormat, options: Options, in directory: URL) async throws
        -> URL
    {
        let output = directory.appending(path: "encoded.\(format.fileExtension)")
        switch format {
        case .jpeg:
            // ImageIO embeds no profile for sRGB bitmaps, so untagged output needs no extra step.
            try writeImageIO(
                image, format: .jpeg, to: output,
                properties: dpiProperties(options.dpi).merging(
                    [kCGImageDestinationLossyCompressionQuality: ImageQualityTable.jpeg(options.quality)]
                ) { $1 })
        case .heic:
            try writeImageIO(
                image, format: .heic, to: output,
                properties: [kCGImageDestinationLossyCompressionQuality: ImageQualityTable.heic(options.quality)])
        case .tiff:
            // Lossless LZW; quality levels do not apply.
            try writeImageIO(
                image, format: .tiff, to: output,
                properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]])
        case .png:
            try await encodePNG(image, options: options, to: output, directory: directory)
        case .webp:
            let lossless = directory.appending(path: "intermediate.png")
            try writeImageIO(image, format: .png, to: lossless, properties: [:])
            guard let cwebp = tools.cwebp else { throw ImageEncodeError.toolMissing(.cwebp) }
            var args = ["-quiet", "-mt", "-q", String(ImageQualityTable.webp(options.quality))]
            args += ["-metadata", options.keepProfile ? "icc" : "none", lossless.path, "-o", output.path]
            try await run(.cwebp, cwebp, args)
        case .avif:
            let lossless = directory.appending(path: "intermediate.png")
            try writeImageIO(image, format: .png, to: lossless, properties: [:])
            guard let avifenc = tools.avifenc else { throw ImageEncodeError.toolMissing(.avifenc) }
            var args = ["-q", String(ImageQualityTable.avif(options.quality)), "--speed", "6", "--jobs", "all"]
            if options.quality != .highest { args += ["--yuv", "420"] }
            args += ["--ignore-exif", "--ignore-xmp"]
            if !options.keepProfile { args.append("--ignore-icc") }
            args += [lossless.path, output.path]
            try await run(.avifenc, avifenc, args)
        }
        return output
    }

    /// Palette quantization with pngquant, falling back to the lossless PNG when it is smaller,
    /// when the quality range cannot be met, at Highest, or when a non-sRGB profile must be kept
    /// (pngquant drops the profile and tags the result sRGB).
    private func encodePNG(_ image: CGImage, options: Options, to output: URL, directory: URL) async throws {
        try writeImageIO(image, format: .png, to: output, properties: dpiProperties(options.dpi))
        let keepsWideProfile = options.keepProfile && !(image.colorSpace.map(ImageRenderer.isDefaultSpace) ?? true)
        guard let range = ImageQualityTable.pngquant(options.quality), !keepsWideProfile else { return }
        guard let pngquant = tools.pngquant else { throw ImageEncodeError.toolMissing(.pngquant) }

        let quantized = directory.appending(path: "quantized.png")
        // pngquant keeps the pHYs (DPI) chunk of its input; --force overwrites, no --strip.
        let args = [
            "--quality", "\(range.lowerBound)-\(range.upperBound)", "--speed", "3", "--force",
            "--output", quantized.path, output.path,
        ]
        let result = try await runner.run(pngquant, arguments: args, timeout: .seconds(300))
        // Exit 99: the image cannot meet the quality range; keep the lossless file.
        if result.exitCode == 99 { return }
        guard result.exitCode == 0 else { throw ImageEncodeError.toolFailed(.pngquant, result.stderrString) }
        if try fileSize(quantized) < fileSize(output) {
            _ = try FileManager.default.replaceItemAt(output, withItemAt: quantized)
        }
    }

    private func run(_ tool: Tool, _ executable: URL, _ arguments: [String]) async throws {
        let result = try await runner.run(executable, arguments: arguments, timeout: .seconds(600))
        guard result.exitCode == 0 else { throw ImageEncodeError.toolFailed(tool, result.stderrString) }
    }

    private func dpiProperties(_ dpi: (width: Double, height: Double)?) -> [CFString: Any] {
        guard let dpi else { return [:] }
        return [kCGImagePropertyDPIWidth: dpi.width, kCGImagePropertyDPIHeight: dpi.height]
    }

    private func writeImageIO(
        _ image: CGImage, format: ConcreteImageFormat, to url: URL, properties: [CFString: Any]
    ) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format.utType.identifier as CFString, 1, nil)
        else { throw ImageEncodeError.writeFailed(format.rawValue) }
        var props = properties
        props[kCGImagePropertyOrientation] = 1
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageEncodeError.writeFailed(format.rawValue) }
    }
}

/// Current size on disk (not cached, unlike URL resource values).
func fileSize(_ url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
}
