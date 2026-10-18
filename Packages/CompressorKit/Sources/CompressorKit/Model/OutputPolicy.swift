import Foundation

/// Where compressed files go (SPEC §11, §12, §15).
public enum OutputLocation: Codable, Hashable, Sendable {
    case sameAsInput
    case subfolder(String)
    case custom(URL)

    public static let defaultSubfolderName = "compressed"
}

/// Placement rules shared by every engine.
public struct OutputPolicy: Codable, Hashable, Sendable {
    public var location: OutputLocation
    /// Appended to the original file name; supports the tokens in `OutputNamer`.
    public var fileNameFormat: String
    /// Move the input to the Trash after a successful compression.
    public var removeInput: Bool

    public static let defaultFileNameFormat = "_compressed"

    public init(
        location: OutputLocation = .sameAsInput,
        fileNameFormat: String = OutputPolicy.defaultFileNameFormat,
        removeInput: Bool = false
    ) {
        self.location = location
        self.fileNameFormat = fileNameFormat
        self.removeInput = removeInput
    }
}

/// What to carry over from the input file (SPEC §15). DPI of JPEG/PNG and the input's
/// Finder tags are always kept and need no option.
public struct MetadataOptions: Codable, Hashable, Sendable {
    /// EXIF, IPTC and XMP, copied without re-encoding (JPEG, PNG, TIFF output).
    public var retainImageMetadata: Bool
    public var preserveColorProfile: Bool
    public var retainCreationDate: Bool
    public var retainModificationDate: Bool
    /// Finder tags added to every output on top of the input's own tags.
    public var extraFinderTags: [String]

    public init(
        retainImageMetadata: Bool = false,
        preserveColorProfile: Bool = false,
        retainCreationDate: Bool = false,
        retainModificationDate: Bool = false,
        extraFinderTags: [String] = []
    ) {
        self.retainImageMetadata = retainImageMetadata
        self.preserveColorProfile = preserveColorProfile
        self.retainCreationDate = retainCreationDate
        self.retainModificationDate = retainModificationDate
        self.extraFinderTags = extraFinderTags
    }
}
