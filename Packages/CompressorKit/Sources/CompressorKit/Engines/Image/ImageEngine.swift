import CoreGraphics
import Foundation

/// An encoded image waiting in a work directory to be placed by `OutputWriter`.
struct EncodedImage: Sendable {
    let url: URL
    let format: ConcreteImageFormat
    let pixelSize: PixelSize
    /// The output format differs from the input format.
    let formatChanged: Bool
    /// The pixel size differs from the (oriented) input size.
    let resized: Bool
}

/// Compresses one image (SPEC §3): decode with orientation applied, scale down,
/// convert color, encode, then copy metadata losslessly.
public struct ImageEngine: Sendable {
    let tools: ImageTools
    let runner: ProcessRunner

    public init(tools: ImageTools, runner: ProcessRunner = ProcessRunner()) {
        self.tools = tools
        self.runner = runner
    }

    func encode(
        _ input: URL, settings: ImageSettings, metadata: MetadataOptions, workDirectory: URL,
        progress: @Sendable (Double) -> Void
    ) async throws -> EncodedImage {
        let info = try ImageDecoder.info(input)
        let format = ConcreteImageFormat.resolve(settings.format, inputType: info.type)
        let target = ImageResizeMath.targetSize(for: info.size, resize: settings.resize)
        progress(0.1)

        let decoded = try ImageDecoder.decode(input, info: info, maxPixelSize: target.longEdge)
        let space = ImageRenderer.outputColorSpace(
            for: decoded, isGray: info.isGray, preserveProfile: metadata.preserveColorProfile)
        let keepAlpha = info.hasAlpha && format.supportsAlpha
        guard let bitmap = ImageRenderer.render(decoded, colorSpace: space, keepAlpha: keepAlpha) else {
            throw ImageEncodeError.writeFailed(format.rawValue)
        }
        try Task.checkCancellation()
        progress(0.4)

        let encoder = ImageEncoder(tools: tools, runner: runner)
        let options = ImageEncoder.Options(
            quality: settings.quality, dpi: format.keepsDPI ? info.dpi : nil,
            keepProfile: metadata.preserveColorProfile)
        let encoded = try await encoder.encode(bitmap, as: format, options: options, in: workDirectory)
        progress(0.9)

        if metadata.retainImageMetadata, format.supportsMetadataCopy, let tree = ImageDecoder.metadata(input) {
            try ImageMetadataCopier.copy(tree, onto: encoded, format: format)
        }
        let size = PixelSize(width: bitmap.width, height: bitmap.height)
        return EncodedImage(
            url: encoded, format: format, pixelSize: size,
            formatChanged: ConcreteImageFormat(inputType: info.type) != format,
            resized: size != info.size)
    }
}
