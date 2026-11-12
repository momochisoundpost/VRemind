import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ string: String) {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        self.major = parts.indices.contains(0) ? (Self.parseComponent(parts[0])) : 0
        self.minor = parts.indices.contains(1) ? (Self.parseComponent(parts[1])) : 0
        self.patch = parts.indices.contains(2) ? (Self.parseComponent(parts[2])) : 0
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    private static func parseComponent(_ raw: Substring) -> Int {
        if let val = Int(raw) {
            return val
        }
        if let prefix = raw.split(separator: "-").first, let val = Int(prefix) {
            return val
        }
        let digits = raw.prefix(while: { $0.isNumber })
        return Int(digits) ?? 0
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }

    public func isNewerThan(_ other: SemanticVersion) -> Bool {
        self > other
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
