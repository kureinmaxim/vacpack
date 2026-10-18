import CompressorKit
import Foundation

let usage = """
    Usage: mycompressor-cli <command>

    Commands:
      tools [--json]   Show the external tools the engines use, where they are and their versions
      --help           Show this help
    """

/// Prints a line to stderr.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func runTools(json: Bool) async -> Int32 {
    let locator = ToolLocator()
    var rows: [(tool: Tool, path: String?, version: String?)] = []
    for tool in Tool.allCases {
        guard let located = locator.locate(tool) else {
            rows.append((tool, nil, nil))
            continue
        }
        let version = (try? await locator.version(of: located)) ?? nil
        rows.append((tool, located.url.path, version))
    }

    if json {
        let objects = rows.map { row -> [String: String?] in
            ["tool": row.tool.rawValue, "path": row.path, "version": row.version]
        }
        let data = try! JSONSerialization.data(
            withJSONObject: objects.map { $0.compactMapValues { $0 } },
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print(String(decoding: data, as: UTF8.self))
    } else {
        let nameWidth = Tool.allCases.map(\.rawValue.count).max() ?? 0
        for row in rows {
            let name = row.tool.rawValue.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            if let path = row.path {
                print("\(name)  \(path)  \(row.version ?? "(version unknown)")")
            } else {
                print("\(name)  not found")
            }
        }
    }
    return 0
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "tools":
    exit(await runTools(json: arguments.contains("--json")))
case nil, "--help", "-h", "help":
    print(usage)
    exit(arguments.isEmpty ? 1 : 0)
default:
    printError("Unknown command: \(arguments[0])\n\n\(usage)")
    exit(2)
}
