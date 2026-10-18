import AppKit
import CompressorKit
import SwiftUI

/// The empty window: one big target for files, in the icon's colors.
struct DropZone: View {
    let isTargeted: Bool
    let missingTools: [Tool]
    let chooseFiles: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: Brand.icon)
                .resizable()
                .frame(width: 104, height: 104)
                .scaleEffect(isTargeted ? 1.08 : 1)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(isTargeted ? "Drop to add" : "Drop images, videos or folders here")
                    .font(.title.weight(.semibold))
                Text("Compressed right on this Mac. A file that would not get smaller keeps its original.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                KindChip(kind: .image, formats: "JPEG, PNG, HEIC, WebP, AVIF…")
                KindChip(kind: .video, formats: "MP4, MOV, WebM, MKV, AVI…")
                KindChip(kind: .gif, formats: "Animated, or from video")
            }
            Button(action: chooseFiles) {
                Label("Choose Files…", systemImage: "plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(BrandButtonStyle())
            if !missingTools.isEmpty {
                StatusPill(
                    text: "Not installed: \(missingTools.map(\.rawValue).joined(separator: ", "))",
                    symbol: "exclamationmark.triangle.fill", color: .orange)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { frame }
        .padding(18)
        .animation(.spring(duration: 0.3), value: isTargeted)
        .contentShape(Rectangle())
    }

    /// A dashed frame in the icon's gradient that lights up while files hover over the window.
    private var frame: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return
            shape
            .fill(Brand.mustard.opacity(isTargeted ? 0.16 : 0.05))
            .overlay {
                shape
                    .strokeBorder(
                        Brand.tile, style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: isTargeted ? [] : [9, 7])
                    )
                    .opacity(isTargeted ? 1 : 0.55)
            }
    }
}

/// A file kind with its badge and a few of its formats.
private struct KindChip: View {
    let kind: FileKind
    let formats: String

    var body: some View {
        HStack(spacing: 9) {
            KindBadge(kind: kind, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.callout.weight(.semibold))
                Text(formats).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(kind.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
