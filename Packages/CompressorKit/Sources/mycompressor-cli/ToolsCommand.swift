import CompressorKit
import Foundation

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
        printJSON(objects.map { $0.compactMapValues { $0 } })
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

func printJSON(_ object: Any) {
    let data = try! JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}
