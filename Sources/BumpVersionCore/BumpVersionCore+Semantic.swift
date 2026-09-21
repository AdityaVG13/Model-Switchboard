import Foundation

public struct SemanticVersion: Equatable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(parsing raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber),
              parts[2].allSatisfy(\.isNumber)
        else {
            throw BumpVersionError.invalidSemanticVersion(raw)
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var rendered: String {
        "\(major).\(minor).\(patch)"
    }
}

public enum VersionBumpTarget: Equatable, Sendable {
    case major
    case minor
    case patch
    case explicit(SemanticVersion)

    public init(parsing raw: String) throws {
        switch raw {
        case "major":
            self = .major
        case "minor":
            self = .minor
        case "patch":
            self = .patch
        default:
            self = .explicit(try SemanticVersion(parsing: raw))
        }
    }
}
