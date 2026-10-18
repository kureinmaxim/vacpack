import AppKit
import CompressorKit
import SwiftUI

/// Accents come from the app icon (`design/AppIcon.swift`): the tile's mint-to-blue gradient.
/// File kinds use a vintage print palette (mustard, rust, jade, cerulean) instead of the usual pink
/// and violet, so they read apart from the accent and from each other.
enum Brand {
    static let mint = Color(hex: 0x3CF2C6)
    static let cyan = Color(hex: 0x14B4D9)
    static let blue = Color(hex: 0x1D4FD8)
    static let indigo = Color(hex: 0x23157A)

    static let mustard = Color(hex: 0xD9A033)
    static let rust = Color(hex: 0xB5532B)
    static let jade = Color(hex: 0x2F9A76)
    static let cerulean = Color(hex: 0x3F8CC9)
    static let deepBlue = Color(hex: 0x2C5F8A)

    /// The icon's tile, for prominent accents such as savings badges and progress.
    static let tile = LinearGradient(colors: [mint, cyan, blue], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Main buttons: white text stays readable on this end of the tile.
    static let button = LinearGradient(colors: [cyan, blue], startPoint: .leading, endPoint: .trailing)

    /// The app icon from the asset catalog; NSApp.applicationIconImage can be a stale cached copy.
    static var icon: NSImage { NSImage(named: "AppIcon") ?? NSApp.applicationIconImage }

    /// Gradient text that stays readable: deep blue on light backgrounds, mint on dark ones.
    static func ink(_ scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark ? [mint, cyan] : [blue, indigo]
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
        case .image: Brand.mustard
        case .video: Brand.rust
        case .gif: Brand.jade
        case .pdf: Brand.cerulean
        case .epub: Brand.deepBlue
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

/// The main action, filled with the icon's gradient. Unlike `.borderedProminent` it keeps its color
/// when the window is not active.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Brand.button, in: Capsule())
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

/// Soft light from the icon's colors behind the window content.
struct BrandBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let strength = scheme == .dark ? 0.20 : 0.11
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Brand.mint.opacity(strength), .clear], center: .topLeading, startRadius: 0, endRadius: 560)
            RadialGradient(
                colors: [Brand.blue.opacity(strength), .clear], center: .bottomTrailing, startRadius: 0,
                endRadius: 680)
            RadialGradient(
                colors: [Brand.mustard.opacity(strength * 0.6), .clear], center: .topTrailing, startRadius: 0,
                endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
