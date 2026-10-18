import Foundation

/// Moves files to the Trash. A protocol so tests do not fill the user's Trash.
public protocol FileTrasher: Sendable {
    func trash(_ url: URL) throws
}

public struct SystemTrasher: FileTrasher {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// File-system facts captured from the input before it may be moved to the Trash.
struct FileFacts: Sendable {
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?
    let tags: [String]

    init(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        creationDate = attributes[.creationDate] as? Date
        modificationDate = attributes[.modificationDate] as? Date
        tags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    /// Applies the dates the options ask for and the Finder tags (input's own plus extra ones; SPEC §15).
    func apply(to output: URL, options: MetadataOptions) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        if options.retainCreationDate, let creationDate { attributes[.creationDate] = creationDate }
        if options.retainModificationDate, let modificationDate { attributes[.modificationDate] = modificationDate }
        if !attributes.isEmpty { try FileManager.default.setAttributes(attributes, ofItemAtPath: output.path) }

        var allTags = tags
        for tag in options.extraFinderTags where !allTags.contains(tag) { allTags.append(tag) }
        if !allTags.isEmpty {
            try (output as NSURL).setResourceValue(allTags, forKey: .tagNamesKey)
        }
    }
}
