import Foundation

/// Places an encoded file next to (or away from) its input, following `OutputPolicy`.
struct OutputWriter: Sendable {
    let trasher: any FileTrasher

    /// The folder outputs for `input` go to, created if needed.
    static func outputDirectory(for input: URL, location: OutputLocation) throws -> URL {
        let directory: URL =
            switch location {
            case .sameAsInput: input.deletingLastPathComponent()
            case .subfolder(let name):
                input.deletingLastPathComponent().appending(path: name.isEmpty ? "compressed" : name)
            case .custom(let url): url
            }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Moves `file` to its final name and handles the input. The input is trashed only after
    /// the output exists; if taking the input's name, the input is trashed first and the output
    /// moved into its place (the input stays recoverable from the Trash).
    func place(
        _ file: URL, fileExtension: String, input: URL, facts: FileFacts, policy: OutputPolicy,
        metadata: MetadataOptions, tokens: OutputNamer.Tokens, directory: URL
    ) throws -> (url: URL, removedInput: Bool) {
        let takesInputName =
            policy.removeInput && directory.standardizedFileURL == input.deletingLastPathComponent().standardizedFileURL
        let suffix = takesInputName ? "" : OutputNamer.expand(policy.fileNameFormat, tokens: tokens)
        let destination = OutputNamer.destination(
            for: input, in: directory, fileExtension: fileExtension, suffix: suffix, replacingInput: takesInputName)

        var removedInput = false
        if destination.standardizedFileURL.path == input.standardizedFileURL.path {
            try trasher.trash(input)
            removedInput = true
        }
        try FileManager.default.moveItem(at: file, to: destination)
        try facts.apply(to: destination, options: metadata)
        if policy.removeInput, !removedInput {
            try trasher.trash(input)
            removedInput = true
        }
        return (destination, removedInput)
    }
}
