import Foundation

public enum BumpVersionError: Error, CustomStringConvertible, Equatable {
    case invalidSemanticVersion(String)
    case missingProjectVersions
    case missingReadmeBadge
    case changelogAlreadyContains(String)
    case missingRequiredFile(String)
    case invalidDate(String)

    public var description: String {
        switch self {
        case .invalidSemanticVersion(let raw):
            return "invalid semantic version: \(raw)"
        case .missingProjectVersions:
            return "project.yml is missing MARKETING_VERSION or CURRENT_PROJECT_VERSION"
        case .missingReadmeBadge:
            return "README.md version badge not found"
        case .changelogAlreadyContains(let header):
            return "CHANGELOG.md already contains \(header)"
        case .missingRequiredFile(let path):
            return "missing required file: \(path)"
        case .invalidDate(let raw):
            return "invalid --date value: \(raw)"
        }
    }
}

public enum BumpVersionCore {
    public static func nextVersion(current: SemanticVersion, target: VersionBumpTarget) -> SemanticVersion {
        switch target {
        case .major:
            return SemanticVersion(major: current.major + 1, minor: 0, patch: 0)
        case .minor:
            return SemanticVersion(major: current.major, minor: current.minor + 1, patch: 0)
        case .patch:
            return SemanticVersion(major: current.major, minor: current.minor, patch: current.patch + 1)
        case .explicit(let version):
            return version
        }
    }
}
