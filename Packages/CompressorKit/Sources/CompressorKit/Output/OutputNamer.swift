import Foundation

/// Builds output file names (SPEC §15, §18).
public enum OutputNamer {
    /// Values for the file name tokens.
    public struct Tokens: Sendable {
        public var date: Date
        public var quality: String?
        public var resolution: String?

        public init(date: Date = Date(), quality: String? = nil, resolution: String? = nil) {
            self.date = date
            self.quality = quality
            self.resolution = resolution
        }
    }

    /// Expands `{timestamp}`, `{datetime}`, `{date}`, `{time}`, `{quality}` and `{resolution}`.
    /// Unknown tokens are left as written. Path separators are replaced so the result stays one name.
    public static func expand(_ format: String, tokens: Tokens) -> String {
        let posix = { (pattern: String) -> String in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter.string(from: tokens.date)
        }
        var result = format
        let values: [(String, String)] = [
            ("{timestamp}", String(Int(tokens.date.timeIntervalSince1970))),
            ("{datetime}", posix("yyyy-MM-dd'T'HHmmss")),
            ("{date}", posix("yyyy-MM-dd")),
            ("{time}", posix("HHmmss")),
            ("{quality}", tokens.quality ?? ""),
            ("{resolution}", tokens.resolution ?? ""),
        ]
        for (token, value) in values { result = result.replacingOccurrences(of: token, with: value) }
        return result.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    /// The destination for one output: `<stem><suffix>.<ext>` in `directory`, numbered
    /// (`name 1`, `name 2`, …) when the name is taken. `replacingInput` lets the output take the
    /// input's own name, used when the input is about to be moved to the Trash.
    public static func destination(
        for input: URL, in directory: URL, fileExtension: String, suffix: String, replacingInput: Bool = false,
        fileManager: FileManager = .default
    ) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent + suffix
        let inputPath = input.standardizedFileURL.path
        func isFree(_ url: URL) -> Bool {
            if url.standardizedFileURL.path == inputPath { return replacingInput }
            return !fileManager.fileExists(atPath: url.path)
        }
        var candidate = directory.appending(path: "\(stem).\(fileExtension)")
        var number = 1
        while !isFree(candidate) {
            candidate = directory.appending(path: "\(stem) \(number).\(fileExtension)")
            number += 1
        }
        return candidate
    }
}
