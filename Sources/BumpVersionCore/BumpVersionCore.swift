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

    public static func replaceProjectVersions(_ text: String, version: String) throws -> String {
        let pattern = #"^(\s+)(MARKETING_VERSION|CURRENT_PROJECT_VERSION):\s+\d+\.\d+\.\d+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            throw BumpVersionError.missingProjectVersions
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let count = regex.numberOfMatches(in: text, options: [], range: range)
        guard count >= 2 else {
            throw BumpVersionError.missingProjectVersions
        }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "$1$2: \(version)"
        )
    }

    public static func replaceReadmeBadge(_ text: String, version: String) throws -> String {
        let pattern = #"version-\d+\.\d+\.\d+-blue"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw BumpVersionError.missingReadmeBadge
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              let matchRange = Range(match.range, in: text)
        else {
            throw BumpVersionError.missingReadmeBadge
        }
        return text.replacingCharacters(in: matchRange, with: "version-\(version)-blue")
    }

    public static func insertChangelogEntry(_ text: String, version: String, entryDate: String) throws -> String {
        let header = "## [\(version)]"
        if text.contains(header) {
            throw BumpVersionError.changelogAlreadyContains(header)
        }
        let entry = """
        \(header) - \(entryDate)

        ### Added
        - TBD

        ### Changed
        - TBD

        ### Fixed
        - TBD

        """
        if let marker = text.range(of: "\n## [") {
            let afterNewline = text.index(after: marker.lowerBound)
            return String(text[..<afterNewline]) + entry + String(text[afterNewline...])
        }
        return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) + "\n\n" + entry
    }

    public static func validateISODate(_ raw: String) throws {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: raw) != nil else {
            throw BumpVersionError.invalidDate(raw)
        }
    }

    public static func bump(root: URL, targetRaw: String, entryDate: String) throws -> (old: String, new: String) {
        try validateISODate(entryDate)
        let versionPath = root.appendingPathComponent("VERSION")
        let projectPath = root.appendingPathComponent("project.yml")
        let readmePath = root.appendingPathComponent("README.md")
        let changelogPath = root.appendingPathComponent("CHANGELOG.md")
        for path in [versionPath, projectPath, readmePath, changelogPath] {
            guard FileManager.default.isReadableFile(atPath: path.path) else {
                throw BumpVersionError.missingRequiredFile(path.path)
            }
        }
        let currentRaw = try String(contentsOf: versionPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let current = try SemanticVersion(parsing: currentRaw)
        let target = try VersionBumpTarget(parsing: targetRaw)
        let next = nextVersion(current: current, target: target)
        let newVersion = next.rendered

        let projectText = try String(contentsOf: projectPath, encoding: .utf8)
        let readmeText = try String(contentsOf: readmePath, encoding: .utf8)
        let changelogText = try String(contentsOf: changelogPath, encoding: .utf8)

        try (newVersion + "\n").write(to: versionPath, atomically: true, encoding: .utf8)
        try replaceProjectVersions(projectText, version: newVersion)
            .write(to: projectPath, atomically: true, encoding: .utf8)
        try replaceReadmeBadge(readmeText, version: newVersion)
            .write(to: readmePath, atomically: true, encoding: .utf8)
        try insertChangelogEntry(changelogText, version: newVersion, entryDate: entryDate)
            .write(to: changelogPath, atomically: true, encoding: .utf8)

        return (currentRaw, newVersion)
    }
}
