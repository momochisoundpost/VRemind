import Foundation
import Testing
@testable import VRemindKit

struct ElapsedTimeTests {
    @Test func elapsedFormatting() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(42 * 60)) == "42m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(2 * 3600 + 5 * 60)) == "2h 05m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(2 * 3600 + 5 * 60 + 59)) == "2h 05m")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(3 * 86400 + 4 * 3600)) == "3d 4h")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(3 * 86400 + 4 * 3600 + 50 * 60)) == "3d 4h")
        #expect(ElapsedTime.short(from: start, to: start.addingTimeInterval(-60)) == "0m")
    }
}
