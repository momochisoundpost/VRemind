import Foundation

public enum SecretCheck: Sendable {
    private static let key: UInt8 = 0x5a

    private static let targetBytes: [UInt8] = [55, 59, 46, 41, 47, 51, 48, 47, 54, 51, 59, 52, 57, 50]
    private static let titleBytes: [UInt8] = [25, 8, 19, 14, 19, 25, 27, 22, 122, 9, 3, 9, 14, 31, 23, 122, 31, 8, 8, 21, 8, 122, 114, 25, 53, 62, 63, 96, 122, 106, 34, 104, 106, 5, 30, 31, 24, 14, 5, 15, 20, 8, 31, 9, 21, 22, 12, 31, 30, 115]
    private static let messageBytes: [UInt8] = [30, 63, 44, 51, 57, 63, 122, 50, 59, 54, 46, 63, 62, 96, 122, 15, 52, 40, 63, 41, 53, 54, 44, 63, 62, 122, 56, 59, 54, 59, 52, 57, 63, 122, 114, 126, 105, 104, 116, 106, 106, 115, 122, 62, 63, 46, 63, 57, 46, 63, 62, 122, 53, 52, 122, 46, 59, 40, 61, 63, 46, 122, 63, 52, 46, 51, 46, 35, 116, 122, 27, 56, 53, 40, 46, 118, 122, 19, 61, 52, 53, 40, 63, 118, 122, 25, 59, 52, 57, 63, 54, 101]
    private static let abortBytes: [UInt8] = [27, 56, 53, 40, 46]
    private static let cancelBytes: [UInt8] = [25, 59, 52, 57, 63, 54]
    private static let ignoreBytes: [UInt8] = [19, 61, 52, 53, 40, 63]

    private static func decode(_ bytes: [UInt8]) -> String {
        let decoded = bytes.map { $0 ^ key }
        return String(decoding: decoded, as: UTF8.self)
    }

    public static func isTarget(_ input: String) -> Bool {
        let handle = WatchedChannel.normalizeHandle(input, for: .youtube) ?? WatchedChannel.normalizeHandle(input, for: .twitch) ?? input
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ \t\n\r")).lowercased()
        guard !clean.isEmpty else { return false }
        return clean == decode(targetBytes)
    }

    public struct DialogStrings: Equatable, Sendable {
        public let title: String
        public let message: String
        public let abort: String
        public let cancel: String
        public let ignore: String
    }

    public static func dialogStrings() -> DialogStrings {
        DialogStrings(
            title: decode(titleBytes),
            message: decode(messageBytes),
            abort: decode(abortBytes),
            cancel: decode(cancelBytes),
            ignore: decode(ignoreBytes)
        )
    }
}
