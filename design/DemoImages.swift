import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Demo photos for README screenshots, drawn in code so they can be published with the project:
// layered ridges under a gradient sky in the app's poster palette, with film grain so they
// compress like real photos.
// Usage: DemoImages <output folder>   (scripts/make-demo.sh)

let folder = URL(filePath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}

struct Scene {
    let name: String
    let type: UTType
    let width: Int
    let height: Int
    let sky: [UInt32]
    let sun: UInt32
    let sunAt: CGPoint  // fractions of the width and height, from the top left
    let sunRadius: CGFloat  // fraction of the height
    let ridges: [UInt32]  // far to near
    let seed: UInt64
}

/// A small deterministic random generator, so every run draws the same scenes.
struct Random {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
}

func render(_ scene: Scene) {
    let width = scene.width
    let height = scene.height
    let w = CGFloat(width)
    let h = CGFloat(height)
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Top-down coordinates.
    context.translateBy(x: 0, y: h)
    context.scaleBy(x: 1, y: -1)

    let sky = CGGradient(
        colorsSpace: space, colors: scene.sky.map { color($0) } as CFArray,
        locations: scene.sky.indices.map { CGFloat($0) / CGFloat(scene.sky.count - 1) })!
    context.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h * 0.75), options: [.drawsAfterEndLocation])

    let sun = CGPoint(x: w * scene.sunAt.x, y: h * scene.sunAt.y)
    let radius = h * scene.sunRadius
    let glow = CGGradient(
        colorsSpace: space, colors: [color(scene.sun, 0.55), color(scene.sun, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(
        glow, startCenter: sun, startRadius: radius, endCenter: sun, endRadius: radius * 5, options: [])
    context.setFillColor(color(scene.sun))
    context.fillEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))

    var random = Random(state: scene.seed)
    for (index, ridge) in scene.ridges.enumerated() {
        let base = h * (0.52 + 0.12 * CGFloat(index))
        let amplitude = h * (0.10 - 0.015 * CGFloat(index))
        let phase = random.next() * 6.3
        let frequency = 1.5 + random.next() * 1.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: h))
        for step in 0...200 {
            let x = w * CGFloat(step) / 200
            let t = Double(step) / 200
            let wave = sin(t * frequency * 6.3 + phase) * 0.6 + sin(t * frequency * 17 + phase * 2) * 0.25
            path.addLine(to: CGPoint(x: x, y: base - amplitude * CGFloat(wave + random.next() * 0.08)))
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color(ridge))
        context.fillPath()
    }

    // Film grain, so the file compresses like a photo rather than a flat drawing.
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for index in 0..<(width * height) {
        let grain = Int(random.next() * 14) - 7
        for channel in 0..<3 {
            let offset = index * 4 + channel
            pixels[offset] = UInt8(clamping: Int(pixels[offset]) + grain)
        }
    }

    let url = folder.appending(path: scene.name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, scene.type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(
        destination, context.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(scene.name)") }
    print("Wrote \(scene.name)")
}

let scenes = [
    Scene(
        name: "Sunset over the ridge.jpg", type: .jpeg, width: 4032, height: 3024,
        sky: [0x2C5F8A, 0xB5532B, 0xE8B84A], sun: 0xFFF1CF, sunAt: CGPoint(x: 0.68, y: 0.46), sunRadius: 0.05,
        ridges: [0x7A3A1C, 0x4E2A1A, 0x2B1A14], seed: 7),
    Scene(
        name: "Morning fog.heic", type: .heic, width: 4032, height: 3024,
        sky: [0x9FC3D8, 0xDCE7E8, 0xF3E9D2], sun: 0xFFF7E2, sunAt: CGPoint(x: 0.3, y: 0.34), sunRadius: 0.04,
        ridges: [0xA9C2BC, 0x6E9C8E, 0x2F7A62], seed: 21),
    Scene(
        name: "Desert dunes.png", type: .png, width: 2400, height: 1600,
        sky: [0x3F8CC9, 0x7DBCE8, 0xF6D774], sun: 0xFFFBEA, sunAt: CGPoint(x: 0.78, y: 0.22), sunRadius: 0.045,
        ridges: [0xE8B84A, 0xD9A033, 0xB5532B], seed: 42),
]
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for scene in scenes { render(scene) }
