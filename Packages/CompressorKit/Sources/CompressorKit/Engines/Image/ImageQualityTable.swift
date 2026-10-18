import Foundation

/// Encoder parameters per quality level. Version 0, chosen by hand; recalibrate against
/// measurements of the original in stage R. Documented in docs/QUALITY.md.
enum ImageQualityTable {
    /// ImageIO JPEG quality, 0…1.
    static func jpeg(_ q: QualityLevel) -> Double {
        switch q {
        case .highest: 0.92
        case .high: 0.82
        case .good: 0.72
        case .medium: 0.60
        case .acceptable: 0.45
        }
    }

    /// ImageIO HEIC quality, 0…1 (HEVC needs less than JPEG for the same look).
    static func heic(_ q: QualityLevel) -> Double {
        switch q {
        case .highest: 0.85
        case .high: 0.70
        case .good: 0.60
        case .medium: 0.50
        case .acceptable: 0.40
        }
    }

    /// pngquant `--quality min-max`; nil means lossless only (no palette quantization).
    static func pngquant(_ q: QualityLevel) -> ClosedRange<Int>? {
        switch q {
        case .highest: nil
        case .high: 80...98
        case .good: 65...90
        case .medium: 50...80
        case .acceptable: 30...70
        }
    }

    /// cwebp `-q`, 0…100.
    static func webp(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 92
        case .high: 82
        case .good: 72
        case .medium: 60
        case .acceptable: 45
        }
    }

    /// avifenc `-q`, 0…100.
    static func avif(_ q: QualityLevel) -> Int {
        switch q {
        case .highest: 85
        case .high: 72
        case .good: 62
        case .medium: 52
        case .acceptable: 40
        }
    }
}
