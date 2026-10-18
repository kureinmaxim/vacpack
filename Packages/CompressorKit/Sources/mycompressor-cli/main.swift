import Foundation

let usage = """
    Usage: mycompressor-cli <command> [options]

    Commands:
      tools [--json]            Show the external tools the engines use, where they are and their versions
      image <files|folders>...  Compress images (run `image --help` for options)
      video <files|folders>...  Compress or convert videos, extract MP3 (run `video --help` for options)
      --help                    Show this help
    """

/// Prints a line to stderr.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "tools":
    exit(await runTools(json: arguments.contains("--json")))
case "image":
    exit(await runCompress(kind: .image, Array(arguments.dropFirst())))
case "video":
    exit(await runCompress(kind: .video, Array(arguments.dropFirst())))
case nil, "--help", "-h", "help":
    print(usage)
    exit(arguments.isEmpty ? 1 : 0)
default:
    printError("Unknown command: \(arguments[0])\n\n\(usage)")
    exit(2)
}
