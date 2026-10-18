import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Vacpack app icon, drawn in code so every size renders crisp from the same vector design:
// a vacuum-sealed pouch (sides pulled in, air leaving through the valve) with a photo inside.
// Palette of an old print poster, shared with the window (App/Design/Brand.swift): mustard paper
// with a rust edge for the tile, a cerulean sky and jade mountains in the photo.
// Usage: AppIcon <output.png> [size]   (scripts/make-icon.sh renders every macOS size)

let output = URL(filePath: CommandLine.arguments[1])
let size = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 1024
let s = CGFloat(size) / 1024  // design units are 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)
// Work top-down like a design tool.
ctx.translateBy(x: 0, y: 1024)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
        ])!
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// MARK: Tile (macOS icon grid: 824 pt body, 100 pt margin)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0xA9761F))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xF6D774), color(0xE8B84A), color(0xD9A033), color(0xB5532B)], [0, 0.32, 0.72, 1]),
    start: CGPoint(x: 260, y: 100), end: CGPoint(x: 764, y: 924),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Soft light from the top left.
ctx.drawRadialGradient(
    gradient([color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)], [0, 1]),
    startCenter: CGPoint(x: 300, y: 220), startRadius: 0, endCenter: CGPoint(x: 300, y: 220), endRadius: 520,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Air leaving the valve: three rising rings.
for (index, ring) in [(512.0, 196.0, 22.0), (556.0, 160.0, 15.0), (478.0, 142.0, 11.0)].enumerated() {
    ctx.setStrokeColor(color(0xFFFFFF, 0.75 - CGFloat(index) * 0.15))
    ctx.setLineWidth(7 - CGFloat(index))
    ctx.strokeEllipse(in: CGRect(x: ring.0 - ring.2, y: ring.1 - ring.2, width: ring.2 * 2, height: ring.2 * 2))
}
ctx.restoreGState()

// MARK: Pouch

let left: CGFloat = 270, right: CGFloat = 754, top: CGFloat = 300, bottom: CGFloat = 800
let pinch: CGFloat = 64  // how far the sides are pulled in by the vacuum
let pouch = CGMutablePath()
pouch.move(to: CGPoint(x: left, y: top))
pouch.addLine(to: CGPoint(x: right, y: top))
pouch.addCurve(
    to: CGPoint(x: right - 6, y: bottom), control1: CGPoint(x: right - pinch, y: top + 150),
    control2: CGPoint(x: right - pinch, y: bottom - 150))
pouch.addQuadCurve(to: CGPoint(x: left + 6, y: bottom), control: CGPoint(x: 512, y: bottom - pinch * 0.9))
pouch.addCurve(
    to: CGPoint(x: left, y: top), control1: CGPoint(x: left + pinch, y: bottom - 150),
    control2: CGPoint(x: left + pinch, y: top + 150))
pouch.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 36, color: color(0x5A3410, 0.45))
ctx.addPath(pouch)
ctx.setFillColor(color(0xFAFCFD))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(pouch)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0xFFFFFF), color(0xEEF2F4), color(0xD3DDE3)], [0, 0.55, 1]),
    start: CGPoint(x: 400, y: top), end: CGPoint(x: 640, y: bottom),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// The photo inside, shrink-wrapped: its outline follows the pinched sides.
let photo = CGMutablePath()
let pl: CGFloat = 352, pr: CGFloat = 672, pt: CGFloat = 430, pb: CGFloat = 712
photo.move(to: CGPoint(x: pl, y: pt))
photo.addLine(to: CGPoint(x: pr, y: pt))
photo.addQuadCurve(to: CGPoint(x: pr, y: pb), control: CGPoint(x: pr - 42, y: (pt + pb) / 2))
photo.addLine(to: CGPoint(x: pl, y: pb))
photo.addQuadCurve(to: CGPoint(x: pl, y: pt), control: CGPoint(x: pl + 42, y: (pt + pb) / 2))
photo.closeSubpath()
ctx.saveGState()
ctx.addPath(photo)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0x7DBCE8), color(0x3F8CC9), color(0x2C5F8A)], [0, 0.5, 1]),
    start: CGPoint(x: 512, y: pt), end: CGPoint(x: 512, y: pb),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Sun and two mountains.
ctx.setFillColor(color(0xF6D774))
ctx.fillEllipse(in: CGRect(x: 560, y: 470, width: 64, height: 64))
let mountains = CGMutablePath()
mountains.move(to: CGPoint(x: pl - 10, y: pb + 10))
mountains.addLine(to: CGPoint(x: 452, y: 548))
mountains.addLine(to: CGPoint(x: 530, y: 640))
mountains.addLine(to: CGPoint(x: 588, y: 590))
mountains.addLine(to: CGPoint(x: pr + 10, y: pb + 10))
mountains.closeSubpath()
ctx.addPath(mountains)
ctx.setFillColor(color(0x2F9A76, 0.95))
ctx.fillPath()
ctx.restoreGState()

// Wrinkles where the film is pulled tight.
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0x98A8B3, 0.55))
ctx.setLineWidth(6)
for wrinkle in [
    (CGPoint(x: 300, y: 360), CGPoint(x: 352, y: 430), CGPoint(x: 318, y: 405)),
    (CGPoint(x: 724, y: 360), CGPoint(x: 672, y: 430), CGPoint(x: 706, y: 405)),
    (CGPoint(x: 305, y: 770), CGPoint(x: 352, y: 712), CGPoint(x: 322, y: 735)),
    (CGPoint(x: 719, y: 770), CGPoint(x: 672, y: 712), CGPoint(x: 702, y: 735)),
] {
    ctx.move(to: wrinkle.0)
    ctx.addQuadCurve(to: wrinkle.1, control: wrinkle.2)
    ctx.strokePath()
}
// Gloss on the film.
let gloss = CGMutablePath()
gloss.move(to: CGPoint(x: 318, y: 330))
gloss.addCurve(to: CGPoint(x: 330, y: 720), control1: CGPoint(x: 352, y: 450), control2: CGPoint(x: 352, y: 600))
ctx.addPath(gloss)
ctx.setStrokeColor(color(0xFFFFFF, 0.8))
ctx.setLineWidth(14)
ctx.strokePath()
ctx.restoreGState()

// MARK: Seal along the top, with a zigzag tear edge

let sealTop: CGFloat = 262
let seal = CGMutablePath()
seal.move(to: CGPoint(x: left - 8, y: top + 18))
seal.addLine(to: CGPoint(x: left - 8, y: sealTop + 12))
let teeth = 14
let step = (right - left + 16) / CGFloat(teeth)
for tooth in 0..<teeth {
    let x = left - 8 + CGFloat(tooth) * step
    seal.addLine(to: CGPoint(x: x + step / 2, y: sealTop))
    seal.addLine(to: CGPoint(x: x + step, y: sealTop + 12))
}
seal.addLine(to: CGPoint(x: right + 8, y: top + 18))
seal.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 10, color: color(0x5A3410, 0.25))
ctx.addPath(seal)
ctx.setFillColor(color(0xF3F6F8))
ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(color(0xB8C6CF, 0.9))
ctx.setLineWidth(4)
for y in [top - 6, top + 6] {
    ctx.move(to: CGPoint(x: left + 4, y: y))
    ctx.addLine(to: CGPoint(x: right - 4, y: y))
    ctx.strokePath()
}

// MARK: Valve

let valve = CGPoint(x: 512, y: 368)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 12, color: color(0x5A3410, 0.4))
ctx.setFillColor(color(0x7A3A1C))
ctx.fillEllipse(in: CGRect(x: valve.x - 46, y: valve.y - 46, width: 92, height: 92))
ctx.restoreGState()
ctx.setStrokeColor(color(0x5CC29C))
ctx.setLineWidth(9)
ctx.strokeEllipse(in: CGRect(x: valve.x - 34, y: valve.y - 34, width: 68, height: 68))
// Up arrow: air goes out.
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(10)
ctx.move(to: CGPoint(x: valve.x, y: valve.y + 18))
ctx.addLine(to: CGPoint(x: valve.x, y: valve.y - 16))
ctx.move(to: CGPoint(x: valve.x - 15, y: valve.y - 2))
ctx.addLine(to: CGPoint(x: valve.x, y: valve.y - 18))
ctx.addLine(to: CGPoint(x: valve.x + 15, y: valve.y - 2))
ctx.strokePath()

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
