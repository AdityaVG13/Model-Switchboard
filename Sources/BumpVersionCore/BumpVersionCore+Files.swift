import Foundation

extension BumpVersionCore {
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
}
