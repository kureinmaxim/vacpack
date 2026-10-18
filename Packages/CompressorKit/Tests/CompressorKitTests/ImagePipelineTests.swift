import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CompressorKit

/// End-to-end image compression through `CompressionPipeline` with the real encoders.
@Suite("Image pipeline", .enabled(if: allImageToolsInstalled, "needs pngquant, cwebp and avifenc"))
struct ImagePipelineTests {
    let dir = TempDirectory("ImagePipeline")
    var bin: URL { dir.url.appending(path: ".trash") }

    /// A high-quality JPEG, so re-encoding at the default level makes it smaller.
    func jpeg(
        _ name: String = "photo.jpg", width: Int = 800, height: Int = 600, quality: Double = 1.0,
        colorSpace: CGColorSpace = TestImage.sRGB, extra: [CFString: Any] = [:]
    ) -> URL {
        var properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        properties.merge(extra) { $1 }
        return TestImage.write(
            TestImage.make(width: width, height: height, colorSpace: colorSpace), to: dir.file(name), type: .jpeg,
            properties: properties)
    }

    func request(
        _ input: URL, _ image: ImageSettings = ImageSettings(), output: OutputPolicy = OutputPolicy(),
        metadata: MetadataOptions = MetadataOptions()
    ) -> JobRequest {
        JobRequest(input: input, image: image, output: output, metadata: metadata)
    }

    // MARK: Compression and formats

    @Test func compressesJPEGNextToInput() async throws {
        let input = jpeg()
        let result = try #require(await compress(request(input), trashBin: bin).result)
        #expect(result.output.lastPathComponent == "photo_compressed.jpg")
        #expect(result.outputBytes < result.inputBytes)
        #expect(TestImage.size(result.output) == result.outputBytes)
        #expect(TestImage.typeIdentifier(result.output) == UTType.jpeg.identifier)
        #expect(result.pixelSize == PixelSize(width: 800, height: 600))
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(dir.contents() == ["photo.jpg", "photo_compressed.jpg"])
    }

    /// Every input format from SPEC §1 produces a valid file in the format "Same as input" maps to.
    @Test(arguments: ["png", "heic", "tiff", "bmp", "webp", "avif", "svg"])
    func sameFormatPerInput(ext: String) async throws {
        // PNG gets a flat-color graphic (what PNG is for); the others a photo-like image.
        let image =
            ext == "png"
            ? TestImage.makeGraphic(width: 640, height: 480, alpha: true) : TestImage.make(width: 640, height: 480)
        let input = dir.file("input.\(ext)")
        let expected: UTType
        switch ext {
        case "png":
            TestImage.write(image, to: input, type: .png)
            expected = .png
        case "heic":
            TestImage.write(
                image, to: input, type: .heic, properties: [kCGImageDestinationLossyCompressionQuality: 1.0])
            expected = .heic
        case "tiff":
            TestImage.write(image, to: input, type: .tiff)
            expected = .tiff
        case "bmp":
            TestImage.write(image, to: input, type: .bmp)
            expected = .png
        case "webp":
            let png = TestImage.write(image, to: dir.file("source.png"), type: .png)
            _ = try await ProcessRunner().run(
                try #require(installedImageTools.cwebp), arguments: ["-quiet", "-q", "98", png.path, "-o", input.path]
            ).checked()
            try FileManager.default.removeItem(at: png)
            expected = .webP
        case "avif":
            let png = TestImage.write(image, to: dir.file("source.png"), type: .png)
            _ = try await ProcessRunner().run(
                try #require(installedImageTools.avifenc), arguments: ["-q", "95", png.path, input.path]
            ).checked()
            try FileManager.default.removeItem(at: png)
            expected = UTType("public.avif")!
        default:  // svg
            try """
            <svg xmlns="http://www.w3.org/2000/svg" width="320" height="200">
              <rect width="320" height="200" fill="#3366cc"/><circle cx="160" cy="100" r="60" fill="#ffcc00"/>
            </svg>
            """.write(to: input, atomically: true, encoding: .utf8)
            expected = .png
        }

        let outcome = await compress(request(input), trashBin: bin)
        let result = try #require(outcome.result, "outcome: \(outcome)")
        #expect(TestImage.typeIdentifier(result.output) == expected.identifier)
        #expect(TestImage.decode(result.output) != nil)
        if ext == "svg" { #expect(result.pixelSize == PixelSize(width: 320, height: 200)) }
    }

    @Test(arguments: [(ImageFormatChoice.webp, "org.webmproject.webp"), (.avif, "public.avif"), (.png, "public.png")])
    func convertsJPEG(format: ImageFormatChoice, identifier: String) async throws {
        let input = jpeg()
        let result = try #require(await compress(request(input, ImageSettings(format: format)), trashBin: bin).result)
        #expect(TestImage.typeIdentifier(result.output) == identifier)
        #expect(result.pixelSize == PixelSize(width: 800, height: 600))
    }

    @Test func transparencyBecomesWhiteInJPEG() async throws {
        let input = TestImage.write(
            TestImage.make(width: 200, height: 100, alpha: true), to: dir.file("a.png"), type: .png)
        let result = try #require(await compress(request(input, ImageSettings(format: .jpg)), trashBin: bin).result)
        let pixel = TestImage.pixel(try #require(TestImage.decode(result.output)), x: 10, y: 50)
        #expect(pixel[0] >= 245 && pixel[1] >= 245 && pixel[2] >= 245, "transparent area should be white, got \(pixel)")
    }

    @Test func transparencyIsKeptInPNG() async throws {
        let input = TestImage.write(
            TestImage.makeGraphic(width: 200, height: 100, alpha: true), to: dir.file("a.png"), type: .png)
        let result = try #require(await compress(request(input), trashBin: bin).result)
        #expect(TestImage.properties(result.output)[kCGImagePropertyHasAlpha] as? Bool == true)
        #expect(TestImage.pixel(try #require(TestImage.decode(result.output)), x: 10, y: 50)[3] == 0)
    }

    // MARK: Never larger (SPEC §8)

    @Test func keepsOriginalWhenNotSmaller() async throws {
        let input = jpeg(quality: 0.2)
        let outcome = await compress(request(input, ImageSettings(quality: .highest)), trashBin: bin)
        #expect(outcome == .keptOriginal(input: input, copiedTo: nil))
        #expect(dir.contents() == ["photo.jpg"])
    }

    @Test func copiesOriginalIntoOtherFolderWhenNotSmaller() async throws {
        let input = jpeg(quality: 0.2)
        let outcome = await compress(
            request(input, ImageSettings(quality: .highest), output: OutputPolicy(location: .subfolder("out"))),
            trashBin: bin)
        guard case .keptOriginal(_, let copy?) = outcome else {
            Issue.record("expected a copy, got \(outcome)")
            return
        }
        #expect(copy.deletingLastPathComponent().lastPathComponent == "out")
        #expect(try Data(contentsOf: copy) == Data(contentsOf: input))
    }

    @Test func neverTrashesInputWhenKeptOriginal() async throws {
        let input = jpeg(quality: 0.2)
        let outcome = await compress(
            request(input, ImageSettings(quality: .highest), output: OutputPolicy(removeInput: true)), trashBin: bin)
        #expect(outcome == .keptOriginal(input: input, copiedTo: nil))
        #expect(FileManager.default.fileExists(atPath: input.path))
        #expect(RecordingTrasher(bin: bin).trashedNames.isEmpty)
    }

    // MARK: Resize

    @Test func resizesByLongEdgeAndNamesWithTokens() async throws {
        let input = jpeg(width: 1200, height: 800)
        let settings = ImageSettings(quality: .good, resize: .maxLongEdge(400))
        let result = try #require(
            await compress(
                request(input, settings, output: OutputPolicy(fileNameFormat: "-{quality}-{resolution}")),
                trashBin: bin
            ).result)
        #expect(result.pixelSize == PixelSize(width: 400, height: 267))
        #expect(result.output.lastPathComponent == "photo-Good-400x267.jpg")
    }

    @Test func appliesOrientationToPixels() async throws {
        // Orientation 6: stored 300×200, displayed rotated 90° → 200×300.
        let input = jpeg(width: 300, height: 200, extra: [kCGImagePropertyOrientation: 6])
        let result = try #require(await compress(request(input), trashBin: bin).result)
        #expect(result.pixelSize == PixelSize(width: 200, height: 300))
        let orientation = TestImage.properties(result.output)[kCGImagePropertyOrientation] as? Int
        #expect(orientation == nil || orientation == 1)
    }

    // MARK: Metadata (SPEC §15)

    var richMetadata: [CFString: Any] {
        [
            kCGImagePropertyDPIWidth: 300, kCGImagePropertyDPIHeight: 300,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:20:30"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "TestCam"],
        ]
    }

    func make(_ props: [CFString: Any]) -> String? {
        (props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
    }

    func exifDate(_ props: [CFString: Any]) -> String? {
        (props[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String
    }

    @Test func stripsMetadataButKeepsDPIByDefault() async throws {
        let input = jpeg(colorSpace: TestImage.displayP3, extra: richMetadata)
        let result = try #require(await compress(request(input), trashBin: bin).result)
        let props = TestImage.properties(result.output)
        #expect(props[kCGImagePropertyDPIWidth] as? Int == 300)
        #expect(make(props) == nil)
        #expect(exifDate(props) == nil)
        // Converted to sRGB, which ImageIO writes without an embedded profile.
        #expect(props[kCGImagePropertyProfileName] as? String != "Display P3")
        #expect(try Data(contentsOf: result.output).range(of: Data("ICC_PROFILE".utf8)) == nil)
    }

    @Test(arguments: [ImageFormatChoice.same, .png])
    func retainsMetadataLosslessly(format: ImageFormatChoice) async throws {
        let input = jpeg(extra: richMetadata)
        let options = MetadataOptions(retainImageMetadata: true)
        let result = try #require(
            await compress(request(input, ImageSettings(format: format), metadata: options), trashBin: bin).result)
        let props = TestImage.properties(result.output)
        #expect(make(props) == "TestCam")
        #expect(exifDate(props) == "2024:05:01 10:20:30")
        #expect(props[kCGImagePropertyDPIWidth] as? Int == 300)
    }

    @Test func preservesColorProfileWhenAsked() async throws {
        let input = jpeg(colorSpace: TestImage.displayP3)
        let options = MetadataOptions(preserveColorProfile: true)
        let result = try #require(await compress(request(input, metadata: options), trashBin: bin).result)
        #expect(TestImage.properties(result.output)[kCGImagePropertyProfileName] as? String == "Display P3")
    }

    @Test func webpDoesNotCarryDPI() async throws {
        let input = jpeg(extra: richMetadata)
        let result = try #require(await compress(request(input, ImageSettings(format: .webp)), trashBin: bin).result)
        #expect(TestImage.properties(result.output)[kCGImagePropertyDPIWidth] == nil)
    }

    @Test func keepsDatesAndFinderTags() async throws {
        let input = jpeg()
        let created = Date(timeIntervalSince1970: 1_577_966_400)  // 2020-01-02
        let modified = Date(timeIntervalSince1970: 1_578_052_800)  // 2020-01-03
        try FileManager.default.setAttributes(
            [.creationDate: created, .modificationDate: modified], ofItemAtPath: input.path)
        try (input as NSURL).setResourceValue(["Red"], forKey: .tagNamesKey)

        let options = MetadataOptions(
            retainCreationDate: true, retainModificationDate: true, extraFinderTags: ["Compressed"])
        let result = try #require(await compress(request(input, metadata: options), trashBin: bin).result)
        let attributes = try FileManager.default.attributesOfItem(atPath: result.output.path)
        #expect(attributes[.creationDate] as? Date == created)
        #expect(attributes[.modificationDate] as? Date == modified)
        let tags = try URL(filePath: result.output.path).resourceValues(forKeys: [.tagNamesKey]).tagNames
        #expect(tags == ["Red", "Compressed"])
    }

    @Test func datesAreNewWithoutTheOptions() async throws {
        let input = jpeg()
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: input.path)
        let result = try #require(await compress(request(input), trashBin: bin).result)
        let modified = try #require(
            try FileManager.default.attributesOfItem(atPath: result.output.path)[.modificationDate] as? Date)
        #expect(modified.timeIntervalSinceNow > -60)
    }

    // MARK: Remove input (SPEC §11)

    @Test func removeInputTakesItsNameAndTrashesIt() async throws {
        let input = jpeg()
        let result = try #require(
            await compress(request(input, output: OutputPolicy(removeInput: true)), trashBin: bin).result)
        #expect(result.output.lastPathComponent == "photo.jpg")
        #expect(result.notes.contains(.removedInput))
        #expect(dir.contents() == ["photo.jpg"])
        #expect(RecordingTrasher(bin: bin).trashedNames == ["photo.jpg"])
        #expect(TestImage.size(result.output) == result.outputBytes)
    }

    @Test func removeInputWithNewFormat() async throws {
        let input = jpeg()
        let result = try #require(
            await compress(
                request(input, ImageSettings(format: .webp), output: OutputPolicy(removeInput: true)), trashBin: bin
            )
            .result)
        #expect(result.output.lastPathComponent == "photo.webp")
        #expect(dir.contents() == ["photo.webp"])
    }

    // MARK: Errors

    @Test func reportsUnsupportedKinds() async throws {
        // PDF arrives in stage 4.
        let pdf = dir.file("doc.pdf")
        try Data([0, 1, 2]).write(to: pdf)
        #expect(await compress(request(pdf), trashBin: bin) == .unsupported(input: pdf, kind: .pdf))
        let unknown = dir.file("notes.txt")
        try Data([0]).write(to: unknown)
        #expect(await compress(request(unknown), trashBin: bin) == .unsupported(input: unknown, kind: nil))
    }

    @Test func failsCleanlyOnBrokenImage() async throws {
        let broken = dir.file("broken.jpg")
        try Data("not an image".utf8).write(to: broken)
        let outcome = await compress(request(broken), trashBin: bin)
        guard case .failed = outcome else {
            Issue.record("expected failure, got \(outcome)")
            return
        }
        #expect(dir.contents() == ["broken.jpg"])
    }
}
