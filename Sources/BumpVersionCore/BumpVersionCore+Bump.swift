import Foundation

extension BumpVersionCore {
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
