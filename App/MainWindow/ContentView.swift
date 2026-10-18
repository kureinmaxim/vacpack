import AppKit
import CompressorKit
import SwiftUI

/// Stage 1 main window: drop images, pick options, compress, see sizes before and after.
/// The full window (previews, presets, per-file settings) arrives in stage 7.
struct ContentView: View {
    @State private var model = CompressionModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                emptyState
            } else {
                FileList(model: model)
            }
            Divider()
            OptionsBar(model: model)
        }
        .frame(minWidth: 720, minHeight: 460)
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(6)
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
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop images, videos or folders here")
                .font(.title2)
            Text("JPEG, PNG, WebP, AVIF, HEIC, TIFF, BMP, DNG, SVG · GIF · MP4, MOV, WebM, MKV, AVI…")
                .foregroundStyle(.secondary)
            Button("Choose Files…", action: chooseFiles)
                .padding(.top, 6)
            if !model.missingTools.isEmpty {
                Label(
                    "Not installed: \(model.missingTools.map(\.rawValue).joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityIdentifier("dropArea")
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

private struct FileList: View {
    let model: CompressionModel

    var body: some View {
        List(model.items) { item in
            FileRow(item: item)
        }
        .accessibilityIdentifier("fileList")
    }
}

private struct FileRow: View {
    let item: CompressionModel.Item

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailStyle)
                    .accessibilityIdentifier("fileDetail")
            }
            Spacer()
            status
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        let input = bytes(item.inputBytes)
        switch item.state {
        case .ready, .queued, .running: return input
        case .done(.compressed(let result)):
            let saved = Int((result.savedFraction * 100).rounded())
            var text = "\(input) → \(bytes(result.outputBytes))  ·  "
            text += saved >= 0 ? "−\(saved)%" : "+\(-saved)%"
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
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running(let fraction): ProgressView(value: fraction).frame(width: 80)
        case .done(.compressed(let result)):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([result.output])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        case .done(.keptOriginal): Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .done(.failed), .done(.unsupported): Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .done(.cancelled): Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

private struct OptionsBar: View {
    @Bindable var model: CompressionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                Spacer()
                if let saved = model.totalSaved {
                    Text("Saved \(bytes(saved.input - saved.output))")
                        .foregroundStyle(.secondary)
                }
                if model.isCompressing {
                    Button("Cancel", action: model.cancel)
                } else {
                    Button("Clear", action: model.clear)
                        .disabled(model.items.isEmpty)
                }
                Button("Compress") {
                    if !model.canCompress { model.resetFinished() }
                    model.compress()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.items.isEmpty || model.isCompressing)
                .accessibilityIdentifier("compressButton")
            }
        }
        .padding(12)
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
            Label("Images", systemImage: "photo").labelStyle(.titleAndIcon).frame(width: 80, alignment: .leading)
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
            .padding(.leading, 94)
        }
        .onChange(of: resolution) { model.videoSettings.resolution = resolution.value }
    }

    private var pickers: some View {
        HStack(spacing: 14) {
            Label("Videos", systemImage: "film").labelStyle(.titleAndIcon).frame(width: 80, alignment: .leading)
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
            Label("GIF", systemImage: "square.stack").labelStyle(.titleAndIcon).frame(width: 80, alignment: .leading)
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

private func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

#Preview {
    ContentView()
}
