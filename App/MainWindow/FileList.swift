import AppKit
import CompressorKit
import QuickLookThumbnailing
import SwiftUI

/// Files as cards: thumbnail, name, sizes and a colored state on the right.
struct FileList: View {
    let model: CompressionModel

    var body: some View {
        Group {
            #if DEBUG
                if WindowSnapshot.isActive {
                    rows.frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView { rows }
                }
            #else
                ScrollView { rows }
            #endif
        }
        .accessibilityIdentifier("fileList")
    }

    private var rows: some View {
        LazyVStack(spacing: 8) {
            ForEach(model.items) { FileRow(item: $0) }
        }
        .padding(16)
    }
}

private struct FileRow: View {
    let item: CompressionModel.Item
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: item.url, kind: item.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.url.lastPathComponent)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(detailStyle)
                    .lineLimit(2)
                    .accessibilityIdentifier("fileDetail")
            }
            Spacer(minLength: 12)
            status
        }
        .padding(10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 1 : 0.82),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
        }
        .onHover { isHovered = $0 }
        // Drag the result (or the original, while there is none) into Mail, Messages or Finder.
        .onDrag { NSItemProvider(contentsOf: resultURL ?? item.url) ?? NSItemProvider() }
        .contextMenu { menu }
    }

    private var resultURL: URL? {
        if case .done(.compressed(let result)) = item.state { result.output } else { nil }
    }

    private var detail: String {
        let input = bytes(item.inputBytes)
        switch item.state {
        case .ready, .queued, .running: return input
        case .done(.compressed(let result)):
            var text = "\(input) → \(bytes(result.outputBytes))"
            if let size = result.pixelSize { text += "  ·  \(size.width)×\(size.height)" }
            if result.output.pathExtension.lowercased() != item.url.pathExtension.lowercased() {
                text += "  ·  \(result.output.pathExtension.uppercased())"
            }
            return text
        case .done(.keptOriginal): return "\(input)  ·  would not get smaller — original kept, no new file"
        case .done(.unsupported): return "Not supported yet"
        case .done(.failed(_, let message)): return message
        case .done(.cancelled): return "\(input)  ·  cancelled"
        }
    }

    private var detailStyle: Color {
        if case .done(.failed) = item.state { return .red }
        return .secondary
    }

    @ViewBuilder private var status: some View {
        switch item.state {
        case .ready: EmptyView()
        case .queued: StatusPill(text: "Waiting", symbol: "clock", color: .secondary)
        case .running(let fraction):
            HStack(spacing: 8) {
                GradientProgress(value: fraction).frame(width: 120)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        case .done(.compressed(let result)):
            HStack(spacing: 10) {
                SavingsBadge(fraction: result.savedFraction)
                // Telegram, Messages, Mail, AirDrop… For apps without a share extension (Delta Chat),
                // drag the row into their window instead.
                ShareLink(item: result.output) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.borderless)
                    .help("Share")
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([result.output])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        case .done(.keptOriginal): StatusPill(text: "Original kept", symbol: "checkmark.circle", color: .secondary)
        case .done(.unsupported): StatusPill(text: "Not supported", symbol: "nosign", color: .secondary)
        case .done(.failed): StatusPill(text: "Failed", symbol: "xmark.octagon", color: .red)
        case .done(.cancelled): StatusPill(text: "Cancelled", symbol: "minus.circle", color: .secondary)
        }
    }

    @ViewBuilder private var menu: some View {
        if let resultURL {
            ShareLink("Share Result…", item: resultURL)
            Button("Show Result in Finder") { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
            Button("Open Result") { NSWorkspace.shared.open(resultURL) }
            Divider()
        }
        Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Button("Open Original") { NSWorkspace.shared.open(item.url) }
    }
}

/// "−87%" printed on the icon's mustard paper; a result that grew on request (another format or
/// size) shows orange.
private struct SavingsBadge: View {
    let fraction: Double

    var body: some View {
        let percent = Int((abs(fraction) * 100).rounded())
        Text(fraction >= 0 ? "−\(percent)%" : "+\(percent)%")
            .font(.callout.weight(.bold).monospacedDigit())
            .foregroundStyle(fraction >= 0 ? Brand.ink : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background {
                if fraction >= 0 {
                    Capsule().fill(Brand.button)
                        .overlay(Capsule().strokeBorder(Brand.ochre.opacity(0.9), lineWidth: 1))
                } else {
                    Capsule().fill(Color.orange.gradient)
                }
            }
            .fixedSize()
    }
}

/// A Quick Look thumbnail of the file (a frame for videos), with the kind badge in the corner.
private struct Thumbnail: View {
    let url: URL
    let kind: FileKind
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(4)
                }
            }
            .frame(width: 48, height: 48)
            .background(kind.tint.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            KindBadge(kind: kind, size: 18)
                .offset(x: 5, y: 5)
        }
        .padding(.trailing, 5)
        .padding(.bottom, 5)
        .task(id: url) {
            if let cgImage = await Self.thumbnail(of: url) {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
            }
        }
    }

    private struct Rendered: @unchecked Sendable { let image: CGImage? }

    private static func thumbnail(of url: URL) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 48, height: 48), scale: 2, representationTypes: .thumbnail)
        let rendered = await withCheckedContinuation { (continuation: CheckedContinuation<Rendered, Never>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: Rendered(image: representation?.cgImage))
            }
        }
        return rendered.image
    }
}

func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}
