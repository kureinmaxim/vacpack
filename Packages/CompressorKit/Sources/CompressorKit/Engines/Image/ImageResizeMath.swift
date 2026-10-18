import Foundation

enum ImageResizeMath {
    /// Output size for a resize mode. Never larger than `source`; aspect ratio kept; at least 1×1.
    static func targetSize(for source: PixelSize, resize: ImageResize) -> PixelSize {
        let scale: Double
        switch resize {
        case .same:
            return source
        case .percentage(let percent):
            scale = Double(percent) / 100
        case .maxWidth(let limit):
            scale = Double(limit) / Double(source.width)
        case .maxHeight(let limit):
            scale = Double(limit) / Double(source.height)
        case .maxLongEdge(let limit):
            scale = Double(limit) / Double(max(source.width, source.height))
        case .maxShortEdge(let limit):
            scale = Double(limit) / Double(min(source.width, source.height))
        }
        guard scale < 1 else { return source }
        return PixelSize(
            width: max(1, Int((Double(source.width) * scale).rounded())),
            height: max(1, Int((Double(source.height) * scale).rounded())))
    }
}
