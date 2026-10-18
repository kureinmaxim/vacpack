import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@testable import CompressorKit

/// A fresh directory removed when the value goes away.
final class TempDirectory: @unchecked Sendable {
    let url: URL

    init(_ name: String = "CompressorKitTests") {
        url = FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func file(_ name: String) -> URL { url.appending(path: name) }

    /// File names in the directory, sorted, without hidden files.
    func contents() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
    }
}

/// Moves "trashed" files into a private folder instead of the user's Trash.
struct RecordingTrasher: FileTrasher {
    let bin: URL

    func trash(_ url: URL) throws {
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: url, to: bin.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)"))
    }

    var trashedNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bin.path)) ?? []).map { String($0.dropFirst(37)) }
    }
}

enum TestImage {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// A photo-like image: smooth gradients plus deterministic noise, so lossy encoders have
    /// real work to do. With `alpha`, the left quarter is fully transparent.
    static func make(width: Int, height: Int, alpha: Bool = false, colorSpace: CGColorSpace = sRGB) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var seed: UInt32 = 0x1234_5678
        func noise() -> Int {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Int(seed >> 27) - 16
        }
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let transparent = alpha && x < width / 4
                let a = transparent ? 0 : 255
                let r = (x * 255 / max(1, width - 1) + noise()).clamped(to: 0...255)
                let g = (y * 255 / max(1, height - 1) + noise()).clamped(to: 0...255)
                let b = ((x + y) * 127 / max(1, width + height) + 64 + noise()).clamped(to: 0...255)
                // Premultiplied: color channels never exceed alpha.
                pixels[i] = UInt8(r * a / 255)
                pixels[i + 1] = UInt8(g * a / 255)
                pixels[i + 2] = UInt8(b * a / 255)
                pixels[i + 3] = UInt8(a)
            }
        }
        return context.makeImage()!
    }

    /// A graphic like a screenshot or logo: a few flat colors, so palette PNG wins clearly.
    /// With `alpha`, the left quarter is fully transparent.
    static func makeGraphic(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        let colors: [CGColor] = [
            CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1), CGColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1),
            CGColor(srgbRed: 0.9, green: 0.2, blue: 0.3, alpha: 1),
            CGColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1),
        ]
        let block = 16
        for y in stride(from: 0, to: height, by: block) {
            for x in stride(from: 0, to: width, by: block) {
                context.setFillColor(colors[(x / block + y / block) % colors.count])
                context.fill(CGRect(x: x, y: y, width: block, height: block))
            }
        }
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width / 4, height: height)) }
        return context.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any] = [:]) -> URL {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination), "could not write \(url.lastPathComponent)")
        return url
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func typeIdentifier(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// RGBA of one pixel after converting to sRGB (y counts from the top).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return data.map(Int.init)
    }

    static func size(_ url: URL) -> Int64 { (try? fileSize(url)) ?? -1 }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// Tools found on this Mac; tests that need a missing tool are skipped.
let installedImageTools = ImageTools(locator: ToolLocator())
let allImageToolsInstalled =
    installedImageTools.pngquant != nil && installedImageTools.cwebp != nil && installedImageTools.avifenc != nil

func makePipeline(trashBin: URL) -> CompressionPipeline {
    CompressionPipeline(
        image: ImageEngine(tools: installedImageTools), video: VideoEngine(locator: ToolLocator()),
        trasher: RecordingTrasher(bin: trashBin))
}

/// Runs one request through the pipeline.
func compress(_ request: JobRequest, trashBin: URL) async -> JobOutcome {
    await makePipeline(trashBin: trashBin).process(request) { _ in }
}

extension JobOutcome {
    var result: CompressionResult? {
        if case .compressed(let result) = self { result } else { nil }
    }
}
