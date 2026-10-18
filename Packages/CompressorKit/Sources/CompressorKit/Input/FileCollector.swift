import Foundation

/// Turns dropped or listed items into the files to compress.
public enum FileCollector {
    /// Files are kept as given; folders are expanded (recursively when `includeSubfolders`),
    /// skipping hidden files and anything `FileKind` does not recognize. Order is stable and
    /// duplicates are removed.
    public static func collect(_ items: [URL], includeSubfolders: Bool = true) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        func add(_ url: URL) {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted { result.append(url) }
        }
        for item in items {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else {
                add(item)
                continue
            }
            var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            if !includeSubfolders { options.insert(.skipsSubdirectoryDescendants) }
            let enumerator = FileManager.default.enumerator(
                at: item, includingPropertiesForKeys: [.isRegularFileKey], options: options)
            var found: [URL] = []
            while let url = enumerator?.nextObject() as? URL {
                let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                if isFile, FileKind.detect(url) != nil { found.append(url) }
            }
            found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.forEach(add)
        }
        return result
    }
}
