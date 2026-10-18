import CompressorKit
import Foundation
import Testing

@Suite("VacpackVersion")
struct VersionTests {
    @Test func versionIsMajorMinorPatch() {
        #expect(VacpackVersion.number.wholeMatch(of: #/(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)/#) != nil)
    }

    @Test func releaseDateIsARealDayMonthYear() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.isLenient = false
        #expect(formatter.date(from: VacpackVersion.releaseDate) != nil)
    }

    @Test func descriptionNamesBoth() {
        #expect(VacpackVersion.description == "\(VacpackVersion.number) (released \(VacpackVersion.releaseDate))")
    }
}
