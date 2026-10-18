import AppKit
import CompressorKit
import SwiftUI

/// The main window: drop files, pick options, compress, see sizes before and after.
/// The full window (previews, presets, per-file settings) arrives in stage 7.
struct ContentView: View {
    @State private var model = CompressionModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                DropZone(isTargeted: isDropTargeted, missingTools: model.missingTools, chooseFiles: chooseFiles)
                    .accessibilityIdentifier("dropArea")
            } else {
                FileList(model: model)
            }
            OptionsBar(model: model)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(BrandBackdrop())
        .tint(Brand.blue)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            // The empty window lights up its own frame; a list gets one around the whole window.
            if isDropTargeted && !model.items.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Brand.tile, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: addFilesFromUITest)
    }

    /// UI tests cannot drag files in or pick menus reliably; they pass paths and the video format
    /// in environment variables instead (Debug only).
    private func addFilesFromUITest() {
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if let format = environment["VACPACK_UITEST_VIDEO_FORMAT"].flatMap(VideoFormatChoice.init) {
                model.videoSettings.format = format
            }
            if let paths = environment["VACPACK_UITEST_FILES"] {
                model.add(paths.split(separator: ":").map { URL(filePath: String($0)) })
            }
            if environment["VACPACK_UITEST_COMPRESS"] == "1" { model.compress() }
            WindowSnapshot.runIfRequested { [model = model] in model.isCompressing }
        #endif
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

/// Settings for the kinds in the list, then the run controls, on a bar at the bottom.
private struct OptionsBar: View {
    @Bindable var model: CompressionModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasImages || model.items.isEmpty {
                ImageOptionsRow(model: model)
            }
            if model.hasVideos {
                VideoOptionsRow(model: model)
            }
            if model.showsGIFOptions {
                GIFOptionsRow(model: model)
            }
            HStack(spacing: 14) {
                Toggle("Remove originals", isOn: $model.output.removeInput)
                    .help("Move originals to the Trash after their compressed copy is saved")
                Spacer()
                if let progress = model.overallProgress {
                    GradientProgress(value: progress).frame(width: 140)
                } else if let saved = model.totalSaved {
                    savedSummary(saved)
                }
                if model.isCompressing {
                    Button("Cancel", action: model.cancel)
                        .controlSize(.large)
                } else {
                    Button("Clear", action: model.clear)
                        .controlSize(.large)
                        .disabled(model.items.isEmpty)
                }
                Button {
                    if !model.canCompress { model.resetFinished() }
                    model.compress()
                } label: {
                    Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                        .padding(.horizontal, 4)
                }
                .buttonStyle(BrandButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(model.items.isEmpty || model.isCompressing)
                .accessibilityIdentifier("compressButton")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func savedSummary(_ saved: (input: Int64, output: Int64)) -> some View {
        let percent = saved.input > 0 ? Int((100 * (1 - Double(saved.output) / Double(saved.input))).rounded()) : 0
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Saved").foregroundStyle(.secondary)
            Text(bytes(max(0, saved.input - saved.output)))
                .font(.title3.weight(.bold))
                .foregroundStyle(Brand.ink(scheme))
            Text(percent >= 0 ? "−\(percent)%" : "+\(-percent)%")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The kind's badge and name at the start of each options row.
private struct KindLabel: View {
    static let width: CGFloat = 96
    let kind: FileKind

    var body: some View {
        HStack(spacing: 7) {
            KindBadge(kind: kind, size: 20)
            Text(kind.title).font(.body.weight(.medium))
        }
        .frame(width: Self.width, alignment: .leading)
    }
}

/// Size limits shared by the image and video rows.
private enum SizeLimit: String, CaseIterable, Identifiable {
    case percentage = "Percentage"
    case maxWidth = "Max width"
    case maxHeight = "Max height"
    case maxLongEdge = "Max long edge"
    case maxShortEdge = "Max short edge"
    var id: String { rawValue }
}

private struct ImageOptionsRow: View {
    @Bindable var model: CompressionModel
    @State private var limit: SizeLimit?
    @State private var value = 1600

    var body: some View {
        HStack(spacing: 14) {
            KindLabel(kind: .image)
            Picker("Quality", selection: $model.imageSettings.quality) {
                ForEach(QualityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            Picker("Format", selection: $model.imageSettings.format) {
                Text("Same as input").tag(ImageFormatChoice.same)
                Text("JPG").tag(ImageFormatChoice.jpg)
                Text("PNG").tag(ImageFormatChoice.png)
                Text("WebP").tag(ImageFormatChoice.webp)
                Text("AVIF").tag(ImageFormatChoice.avif)
            }
            .fixedSize()
            Picker("Size", selection: $limit) {
                Text("Same size").tag(SizeLimit?.none)
                ForEach(SizeLimit.allCases) { Text($0.rawValue).tag(SizeLimit?.some($0)) }
            }
            .fixedSize()
            if let limit {
                TextField("Value", value: $value, format: .number).frame(width: 64)
                Text(limit == .percentage ? "%" : "px").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onChange(of: limit) { apply() }
        .onChange(of: value) { apply() }
    }

    private func apply() {
        let n = max(1, value)
        model.imageSettings.resize =
            switch limit {
            case nil: .same
            case .percentage: .percentage(min(100, n))
            case .maxWidth: .maxWidth(n)
            case .maxHeight: .maxHeight(n)
            case .maxLongEdge: .maxLongEdge(n)
            case .maxShortEdge: .maxShortEdge(n)
            }
    }
}

private struct VideoOptionsRow: View {
    @Bindable var model: CompressionModel

    enum Resolution: String, CaseIterable, Identifiable {
        case same = "Same as input"
        case uhd4K = "4K"
        case fullHD = "Full HD"
        case hd = "HD"
        var id: String { rawValue }

        var value: VideoResolution {
            switch self {
            case .same: .same
            case .uhd4K: .uhd4K
            case .fullHD: .fullHD
            case .hd: .hd
            }
        }
    }

    @State private var resolution = Resolution.same

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pickers
            // Toggles on their own line, so their labels never wrap in a narrow window.
            HStack(spacing: 18) {
                Toggle("Remove audio", isOn: $model.videoSettings.removeAudio)
                    .fixedSize()
                Toggle("Keep transparency", isOn: $model.videoSettings.preserveTransparency)
                    .fixedSize()
                    .help("MOV keeps the alpha channel with HEVC; WebM always keeps it")
                Toggle("Hardware encoding", isOn: $model.videoEncoding.hardwareAcceleration)
                    .fixedSize()
                    .help("VideoToolbox: can be faster on 4K, but visibly lower quality at the same size")
                Spacer()
            }
            .padding(.leading, KindLabel.width + 14)
        }
        .onChange(of: resolution) { model.videoSettings.resolution = resolution.value }
    }

    private var pickers: some View {
        HStack(spacing: 14) {
            KindLabel(kind: .video)
            Picker("Quality", selection: $model.videoSettings.quality) {
                ForEach(QualityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            Picker("Format", selection: $model.videoSettings.format) {
                Text("Same as input").tag(VideoFormatChoice.same)
                Text("MP4").tag(VideoFormatChoice.mp4)
                Text("WebM").tag(VideoFormatChoice.webm)
                Text("MOV").tag(VideoFormatChoice.mov)
                Text("GIF").tag(VideoFormatChoice.gif)
                Text("MP3 (audio)").tag(VideoFormatChoice.mp3)
            }
            .fixedSize()
            Picker("Resolution", selection: $resolution) {
                ForEach(Resolution.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            Spacer()
        }
    }
}

private struct GIFOptionsRow: View {
    @Bindable var model: CompressionModel

    enum Size: Hashable, Identifiable {
        case same, p75, p50, p25, percentage, maxWidth
        var id: Self { self }
        var title: String {
            switch self {
            case .same: "Same as input"
            case .p75: "75%"
            case .p50: "50%"
            case .p25: "25%"
            case .percentage: "Percentage"
            case .maxWidth: "Max width"
            }
        }
    }

    @State private var size = Size.same
    @State private var value = 480

    var body: some View {
        HStack(spacing: 14) {
            KindLabel(kind: .gif)
            Picker("Quality", selection: $model.gifSettings.quality) {
                ForEach(QualityLevel.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            Picker("Size", selection: $size) {
                ForEach([Size.same, .p75, .p50, .p25, .percentage, .maxWidth]) { Text($0.title).tag($0) }
            }
            .fixedSize()
            if size == .percentage || size == .maxWidth {
                TextField("Value", value: $value, format: .number).frame(width: 64)
                Text(size == .percentage ? "%" : "px").foregroundStyle(.secondary)
            }
            if model.hasVideos && model.videoSettings.format == .gif {
                Stepper(
                    "FPS \(model.gifSettings.fps)", value: $model.gifSettings.fps, in: GIFSettings.fpsRange, step: 5
                )
                .help("Frame rate for videos converted to GIF")
            }
            Spacer()
        }
        .onChange(of: size) { apply() }
        .onChange(of: value) { apply() }
    }

    private func apply() {
        let n = max(1, value)
        model.gifSettings.dimension =
            switch size {
            case .same: .same
            case .p75: .percentage(75)
            case .p50: .percentage(50)
            case .p25: .percentage(25)
            case .percentage: .percentage(min(100, n))
            case .maxWidth: .maxWidth(n)
            }
    }
}

#Preview {
    ContentView()
}
