import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CompressorKit

@Suite("File kinds and formats")
struct ModelTests {
    @Test(arguments: [
        ("a.jpg", FileKind.image), ("a.JPEG", .image), ("a.png", .image), ("a.webp", .image), ("a.avif", .image),
        ("a.heic", .image), ("a.heif", .image), ("a.dng", .image), ("a.tiff", .image), ("a.bmp", .image),
        ("a.svg", .image), ("a.gif", .gif), ("a.pdf", .pdf), ("a.epub", .epub), ("a.mp4", .video),
        ("a.mov", .video), ("a.mkv", .video),
    ])
    func detectsKind(name: String, kind: FileKind) {
        #expect(FileKind.detect(URL(filePath: "/tmp/\(name)")) == kind)
    }

    @Test(arguments: ["a.txt", "a.zip", "noextension", "a.psd"])
    func unknownFilesHaveNoKind(name: String) {
        #expect(FileKind.detect(URL(filePath: "/tmp/\(name)")) == nil)
    }

    @Test(arguments: [
        ("jpg", ConcreteImageFormat.jpeg), ("png", .png), ("webp", .webp), ("avif", .avif), ("heic", .heic),
        ("heif", .heic), ("tiff", .tiff), ("dng", .jpeg), ("bmp", .png), ("svg", .png),
    ])
    func sameFormatResolvesPerInput(ext: String, expected: ConcreteImageFormat) throws {
        let type = try #require(UTType(filenameExtension: ext))
        #expect(ConcreteImageFormat.resolve(.same, inputType: type) == expected)
    }

    @Test func explicitFormatWins() {
        #expect(ConcreteImageFormat.resolve(.webp, inputType: .jpeg) == .webp)
        #expect(ConcreteImageFormat.resolve(.jpg, inputType: .png) == .jpeg)
        #expect(ConcreteImageFormat.resolve(.avif, inputType: .heic) == .avif)
        #expect(ConcreteImageFormat.resolve(.png, inputType: .svg) == .png)
    }

    @Test(arguments: [
        (ImageResize.same, PixelSize(width: 1200, height: 800)),
        (.percentage(50), PixelSize(width: 600, height: 400)),
        (.maxWidth(300), PixelSize(width: 300, height: 200)),
        (.maxHeight(400), PixelSize(width: 600, height: 400)),
        (.maxLongEdge(600), PixelSize(width: 600, height: 400)),
        (.maxShortEdge(200), PixelSize(width: 300, height: 200)),
        // Never upscale.
        (.maxLongEdge(5000), PixelSize(width: 1200, height: 800)),
        (.percentage(150), PixelSize(width: 1200, height: 800)),
        // Rounding keeps at least one pixel.
        (.maxShortEdge(1), PixelSize(width: 2, height: 1)),
    ])
    func resizeMath(resize: ImageResize, expected: PixelSize) {
        #expect(ImageResizeMath.targetSize(for: PixelSize(width: 1200, height: 800), resize: resize) == expected)
    }

    @Test func qualityLabels() {
        #expect(QualityLevel.good.label == "Good")
        #expect(QualityLevel.acceptable.label == "Acceptable")
    }
}

@Suite("FileCollector")
struct FileCollectorTests {
    @Test func expandsFoldersSkippingHiddenAndUnsupported() throws {
        let dir = TempDirectory()
        let sub = dir.file("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for name in ["b.jpg", "a.png", ".hidden.jpg", "notes.txt", "sub/c.webp"] {
            try Data([0]).write(to: dir.file(name))
        }
        let all = FileCollector.collect([dir.url]).map(\.lastPathComponent)
        #expect(all == ["a.png", "b.jpg", "c.webp"])
        let flat = FileCollector.collect([dir.url], includeSubfolders: false).map(\.lastPathComponent)
        #expect(flat == ["a.png", "b.jpg"])
    }

    @Test func keepsGivenFilesAndRemovesDuplicates() throws {
        let dir = TempDirectory()
        let file = dir.file("x.jpg")
        try Data([0]).write(to: file)
        let collected = FileCollector.collect([file, dir.url, file, dir.file("missing.jpg")])
        #expect(collected.map(\.lastPathComponent) == ["x.jpg"])
    }
}
