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

    /// UI tests cannot drag files in; they pass paths in an environment variable instead (Debug only).
    private func addFilesFromUITest() {
        #if DEBUG
            if let paths = ProcessInfo.processInfo.environment["MYCOMPRESSOR_UITEST_FILES"] {
                model.add(paths.split(separator: ":").map { URL(filePath: String($0)) })
            }
        #endif
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop images or folders here")
                .font(.title2)
            Text("JPEG, PNG, WebP, AVIF, HEIC, TIFF, BMP, DNG, SVG")
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
        case .done(.keptOriginal): return "\(input)  ·  already optimized, original kept"
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
    @State private var resizeMode = ResizeMode.same
    @State private var resizeValue = 1600

    enum ResizeMode: String, CaseIterable, Identifiable {
        case same = "Same size"
        case percentage = "Percentage"
        case maxWidth = "Max width"
        case maxHeight = "Max height"
        case maxLongEdge = "Max long edge"
        case maxShortEdge = "Max short edge"
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 14) {
            Picker("Quality", selection: $model.settings.quality) {
                ForEach(ImageQuality.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .fixedSize()
            Picker("Format", selection: $model.settings.format) {
                Text("Same as input").tag(ImageFormatChoice.same)
                Text("JPG").tag(ImageFormatChoice.jpg)
                Text("PNG").tag(ImageFormatChoice.png)
                Text("WebP").tag(ImageFormatChoice.webp)
                Text("AVIF").tag(ImageFormatChoice.avif)
            }
            .fixedSize()
            Picker("Size", selection: $resizeMode) {
                ForEach(ResizeMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            if resizeMode != .same {
                TextField("Value", value: $resizeValue, format: .number)
                    .frame(width: 64)
                Text(resizeMode == .percentage ? "%" : "px").foregroundStyle(.secondary)
            }
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
        .padding(12)
        .onChange(of: resizeMode) { applyResize() }
        .onChange(of: resizeValue) { applyResize() }
    }

    private func applyResize() {
        let value = max(1, resizeValue)
        model.settings.resize =
            switch resizeMode {
            case .same: .same
            case .percentage: .percentage(min(100, value))
            case .maxWidth: .maxWidth(value)
            case .maxHeight: .maxHeight(value)
            case .maxLongEdge: .maxLongEdge(value)
            case .maxShortEdge: .maxShortEdge(value)
            }
    }
}

private func bytes(_ count: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
}

#Preview {
    ContentView()
}
