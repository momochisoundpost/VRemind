import Foundation
import Testing
@testable import VRemindKit

struct SecretCheckTests {
    private static let rawBytes: [UInt8] = [55, 59, 46, 41, 47, 51, 48, 47, 54, 51, 59, 52, 57, 50]
    private static var targetHandle: String {
        String(decoding: rawBytes.map { $0 ^ 0x5a }, as: UTF8.self)
    }

    @Test func testIsTargetMatching() {
        let handle = Self.targetHandle
        #expect(SecretCheck.isTarget("@" + handle))
        #expect(SecretCheck.isTarget("@" + handle.lowercased()))
        #expect(SecretCheck.isTarget(handle.lowercased()))
        #expect(SecretCheck.isTarget(handle.uppercased()))
        #expect(SecretCheck.isTarget("  @" + handle + "  "))
        #expect(SecretCheck.isTarget("@" + handle + "\n"))
        #expect(SecretCheck.isTarget("https://www.youtube.com/@" + handle))
        #expect(SecretCheck.isTarget("https://youtube.com/@" + handle.lowercased()))

        // Non-targets
        #expect(!SecretCheck.isTarget("@bukancaitlyn"))
        #expect(!SecretCheck.isTarget("@lortlimbah"))
        #expect(!SecretCheck.isTarget("@jinggaawoo"))
        #expect(!SecretCheck.isTarget(""))
        #expect(!SecretCheck.isTarget("@"))
    }

    @Test func testDialogStringsDecoding() {
        let strings = SecretCheck.dialogStrings()

        #expect(!strings.title.isEmpty)
        #expect(!strings.message.isEmpty)
        #expect(strings.abort == "Abort")
        #expect(strings.cancel == "Cancel")
        #expect(strings.ignore == "Ignore")

        #expect(strings.title.count > 10)
        #expect(strings.message.contains(strings.abort))
        #expect(strings.message.contains(strings.cancel))
        #expect(strings.message.contains(strings.ignore))
    }
}
