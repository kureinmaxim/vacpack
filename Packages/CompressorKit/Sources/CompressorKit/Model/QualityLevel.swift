import Foundation

/// The five quality levels shared by images, videos and GIFs (SPEC §2–§4). Concrete encoder
/// values live in `ImageQualityTable` and `VideoQualityTable` (docs/QUALITY.md).
public enum QualityLevel: String, Codable, Sendable, CaseIterable {
    case highest, high, good, medium, acceptable

    /// Label used in the `{quality}` file name token, e.g. "Good".
    public var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
