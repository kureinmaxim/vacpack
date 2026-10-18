import Foundation

/// Encoder parameters per video quality level. Version 0; see docs/QUALITY.md.
enum VideoQualityTable {
    /// VideoToolbox constant quality (`-q:v`, 1–100, Apple Silicon only) for H.264.
    static func videoToolboxH264(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 68
        case .high: 58
        case .good: 50
        case .medium: 43
        case .acceptable: 35
        }
    }

    /// VideoToolbox constant quality for HEVC (more efficient at the same value).
    static func videoToolboxHEVC(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 65
        case .high: 55
        case .good: 47
        case .medium: 40
        case .acceptable: 32
        }
    }

    /// libx264 `-crf`.
    static func x264(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 18
        case .high: 21
        case .good: 24
        case .medium: 27
        case .acceptable: 30
        }
    }

    /// libx265 `-crf`.
    static func x265(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 21
        case .high: 24
        case .good: 27
        case .medium: 30
        case .acceptable: 33
        }
    }

    /// libvpx-vp9 `-crf` with `-b:v 0` (constant quality).
    static func vp9(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 24
        case .high: 30
        case .good: 34
        case .medium: 38
        case .acceptable: 42
        }
    }
}
