import AppKit
import CompressorKit
import SwiftUI

/// The palette of an old print poster, shared with the app icon (`design/AppIcon.swift`): mustard
/// paper with a rust edge for accents, the photo's cerulean and jade (with rust) for file kinds.
enum Brand {
    static let paper = Color(hex: 0xF6D774)
    static let mustard = Color(hex: 0xE8B84A)
    static let ochre = Color(hex: 0xD9A033)
    static let rust = Color(hex: 0xB5532B)
    static let brown = Color(hex: 0x7A3A1C)
    /// Text on mustard: printed ink.
    static let ink = Color(hex: 0x3A2208)
    static let cerulean = Color(hex: 0x3F8CC9)
    static let jade = Color(hex: 0x2F9A76)
    static let deepBlue = Color(hex: 0x2C5F8A)

    /// The icon's tile, for prominent accents such as savings badges, progress and the drop frame.
    static let tile = LinearGradient(
        colors: [paper, mustard, ochre, rust], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Main buttons and badges: mustard paper, printed in dark ink.
    static let button = LinearGradient(colors: [paper, mustard, ochre], startPoint: .top, endPoint: .bottom)

    /// The app icon from the asset catalog; NSApp.applicationIconImage can be a stale cached copy.
    static var icon: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }

    /// Gradient text that stays readable: rust and brown on light backgrounds, mustard on dark ones.
    static func headline(_ scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark ? [paper, mustard] : [rust, brown]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    /// A Display P3 color from 0xRRGGBB, the color space the icon is drawn in.
    init(hex: UInt32) {
        self.init(
            .displayP3, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

extension FileKind {
    /// One color per kind across the window.
    var tint: Color {
        switch self {
        case .image: Brand.cerulean
        case .video: Brand.jade
        case .gif: Brand.rust
        case .pdf: Brand.deepBlue
        case .epub: Brand.brown
        }
    }

    var symbol: String {
        switch self {
        case .image: "photo"
        case .video: "film"
        case .gif: "square.stack.3d.up"
        case .pdf: "doc.richtext"
        case .epub: "book"
        }
    }

    var title: String {
        switch self {
        case .image: "Images"
        case .video: "Videos"
        case .gif: "GIF"
        case .pdf: "PDF"
        case .epub: "EPUB"
        }
    }
}

/// A rounded square in the kind's color with its symbol, like a tiny app icon.
struct KindBadge: View {
    let kind: FileKind
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The main action on the icon's mustard paper. Unlike `.borderedProminent` it keeps its color when
/// the window is not active.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Brand.button, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.ochre.opacity(0.9), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A small colored capsule for a file's state.
struct StatusPill: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }
}

/// A thin progress bar filled with the icon's gradient.
struct GradientProgress: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Brand.tile)
                    .frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.25), value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
    }
}

/// Warm paper light from the icon's colors behind the window content, with a touch of its sky.
struct BrandBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.20 : 0.11
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Brand.mustard.opacity(strength), .clear], center: .topLeading, startRadius: 0,
                endRadius: 560)
            RadialGradient(
                colors: [Brand.rust.opacity(strength * 0.8), .clear], center: .bottomTrailing, startRadius: 0,
                endRadius: 680)
            RadialGradient(
                colors: [Brand.cerulean.opacity(strength * 0.6), .clear], center: .topTrailing, startRadius: 0,
                endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
