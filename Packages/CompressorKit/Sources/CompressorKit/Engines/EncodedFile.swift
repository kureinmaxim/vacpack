import Foundation

/// An engine's output waiting in a work directory to be placed by `OutputWriter`.
struct EncodedFile: Sendable {
    let url: URL
    let fileExtension: String
    let pixelSize: PixelSize?
    /// The user explicitly asked for another format or size and got it, or the input format cannot
    /// be written back (SVG, BMP, AVI…). Then a larger result is still delivered; otherwise a result
    /// that is not smaller keeps the original (SPEC §8).
    let changedOnRequest: Bool
    /// Value of the `{resolution}` file name token.
    let resolutionLabel: String?
}
