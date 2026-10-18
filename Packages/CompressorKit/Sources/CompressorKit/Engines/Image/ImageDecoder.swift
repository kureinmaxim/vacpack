import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Facts about an input image needed before decoding.
struct SourceImageInfo: Sendable {
    let type: UTType
    /// Size after applying the EXIF orientation.
    let size: PixelSize
    let hasAlpha: Bool
    let isGray: Bool
    let dpi: (width: Double, height: Double)?
    let profileName: String?
}

enum ImageDecodeError: Error, CustomStringConvertible {
    case unreadable(URL)

    var description: String {
        switch self {
        case .unreadable(let url): "Cannot read image \(url.lastPathComponent)"
        }
    }
}

enum ImageDecoder {
    static func info(_ url: URL) throws -> SourceImageInfo {
        let type = UTType(filenameExtension: url.pathExtension.lowercased()) ?? .image
        if type.conforms(to: .svg) { return try svgInfo(url) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ImageDecodeError.unreadable(url) }

        // Orientations 5–8 rotate by 90°, swapping width and height.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let size = orientation >= 5 ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
        let dpi: (Double, Double)? =
            if let x = props[kCGImagePropertyDPIWidth] as? Double, let y = props[kCGImagePropertyDPIHeight] as? Double {
                (x, y)
            } else { nil }
        return SourceImageInfo(
            type: type, size: size,
            hasAlpha: props[kCGImagePropertyHasAlpha] as? Bool ?? false,
            isGray: (props[kCGImagePropertyColorModel] as? String) == (kCGImagePropertyColorModelGray as String),
            dpi: dpi,
            profileName: props[kCGImagePropertyProfileName] as? String)
    }

    /// Decodes the image with its orientation applied, scaled so the long edge is at most `maxPixelSize`.
    static func decode(_ url: URL, info: SourceImageInfo, maxPixelSize: Int) throws -> CGImage {
        if info.type.conforms(to: .svg) { return try renderSVG(url, longEdge: maxPixelSize) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageDecodeError.unreadable(url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageDecodeError.unreadable(url)
        }
        return image
    }

    /// The input's EXIF/IPTC/XMP metadata tree, for lossless copying onto the output.
    static func metadata(_ url: URL) -> CGImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    }

    // MARK: SVG (ImageIO cannot read it; NSImage renders it through CoreSVG)

    private static func svgImage(_ url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw ImageDecodeError.unreadable(url)
        }
        return image
    }

    private static func svgInfo(_ url: URL) throws -> SourceImageInfo {
        let image = try svgImage(url)
        return SourceImageInfo(
            type: .svg,
            size: PixelSize(width: Int(image.size.width.rounded()), height: Int(image.size.height.rounded())),
            hasAlpha: true, isGray: false, dpi: nil, profileName: nil)
    }

    private static func renderSVG(_ url: URL, longEdge: Int) throws -> CGImage {
        let image = try svgImage(url)
        let scale = Double(longEdge) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ImageDecodeError.unreadable(url) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let rendered = context.makeImage() else { throw ImageDecodeError.unreadable(url) }
        return rendered
    }
}

/// Draws an image into an 8-bit bitmap in the requested color space.
enum ImageRenderer {
    /// - Parameters:
    ///   - keepAlpha: keep transparency; otherwise flatten onto white (SPEC §3: PNG → JPG must not turn black).
    ///   - colorSpace: target space. Gray is used only for opaque images (CG has no gray+alpha bitmaps).
    static func render(_ image: CGImage, colorSpace: CGColorSpace, keepAlpha: Bool) -> CGImage? {
        let gray = colorSpace.model == .monochrome && !keepAlpha
        let space = gray || colorSpace.model == .rgb ? colorSpace : CGColorSpace(name: CGColorSpace.sRGB)!
        let alphaInfo: CGImageAlphaInfo = keepAlpha ? .premultipliedLast : (gray ? .none : .noneSkipLast)
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: alphaInfo.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if !keepAlpha {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
        }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// The color space for the output: the input's own when the profile is preserved,
    /// otherwise sRGB (or gamma 2.2 gray for gray images), which is what untagged files mean.
    static func outputColorSpace(for image: CGImage, isGray: Bool, preserveProfile: Bool) -> CGColorSpace {
        if preserveProfile, let space = image.colorSpace, space.model == .rgb || space.model == .monochrome {
            return space
        }
        return isGray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// True when the space is the default an untagged file implies, so its embedded profile can be dropped.
    static func isDefaultSpace(_ space: CGColorSpace) -> Bool {
        let name = space.name as String?
        return name == CGColorSpace.sRGB as String || name == CGColorSpace.genericGrayGamma2_2 as String
    }
}
