import Foundation
import ImageIO
import Testing

@testable import CompressorKit

@Suite("Output naming")
struct OutputNamerTests {
    @Test func expandsAllTokens() {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        formatter.dateFormat = "HHmmss"
        let time = formatter.string(from: date)

        let tokens = OutputNamer.Tokens(date: date, quality: "Good", resolution: "800x600")
        #expect(OutputNamer.expand("-{date}", tokens: tokens) == "-\(day)")
        #expect(OutputNamer.expand("_{time}", tokens: tokens) == "_\(time)")
        #expect(OutputNamer.expand("_{datetime}", tokens: tokens) == "_\(day)T\(time)")
        #expect(OutputNamer.expand("_{timestamp}", tokens: tokens) == "_1780000000")
        #expect(OutputNamer.expand("-{quality}-{resolution}", tokens: tokens) == "-Good-800x600")
        #expect(OutputNamer.expand("_{unknown}", tokens: tokens) == "_{unknown}")
    }

    @Test func pathSeparatorsCannotEscapeTheFolder() {
        #expect(OutputNamer.expand("/../x:y", tokens: .init()) == "-..-x-y")
    }

    @Test func numbersCollisions() throws {
        let dir = TempDirectory()
        let input = dir.file("photo.jpg")
        try Data([0]).write(to: input)
        let first = OutputNamer.destination(for: input, in: dir.url, fileExtension: "jpg", suffix: "_c")
        #expect(first.lastPathComponent == "photo_c.jpg")
        try Data([0]).write(to: first)
        let second = OutputNamer.destination(for: input, in: dir.url, fileExtension: "jpg", suffix: "_c")
        #expect(second.lastPathComponent == "photo_c 1.jpg")
    }

    @Test func emptySuffixNeverOverwritesTheInput() throws {
        let dir = TempDirectory()
        let input = dir.file("photo.jpg")
        try Data([0]).write(to: input)
        let url = OutputNamer.destination(for: input, in: dir.url, fileExtension: "jpg", suffix: "")
        #expect(url.lastPathComponent == "photo 1.jpg")
        let replacing = OutputNamer.destination(
            for: input, in: dir.url, fileExtension: "jpg", suffix: "", replacingInput: true)
        #expect(replacing.lastPathComponent == "photo.jpg")
    }
}
