import CompressorKit
import SwiftUI

/// Placeholder main window for stage 0: shows which external tools were found.
/// The real file list and options sidebar arrive in stages 1 and 7.
struct ContentView: View {
    private let tools: [(tool: Tool, located: LocatedTool?)] = {
        let locator = ToolLocator()
        return Tool.allCases.map { ($0, locator.locate($0)) }
    }()

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop files here")
                    .font(.title2)
                Text("Compression arrives in the next stage.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("dropArea")

            GroupBox("Compression tools") {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(tools, id: \.tool) { row in
                        GridRow {
                            Image(systemName: row.located == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(row.located == nil ? .red : .green)
                            Text(row.tool.rawValue)
                                .fontWeight(.medium)
                            Text(row.located?.url.path ?? String(localized: "not found"))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .accessibilityIdentifier("toolsStatus")
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
