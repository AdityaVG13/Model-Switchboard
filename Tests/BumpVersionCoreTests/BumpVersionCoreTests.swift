import Testing
import BumpVersionCore

@Test func nextVersionIncrementsSemverParts() throws {
    let current = try SemanticVersion(parsing: "1.2.3")
    #expect(BumpVersionCore.nextVersion(current: current, target: .patch).rendered == "1.2.4")
    #expect(BumpVersionCore.nextVersion(current: current, target: .minor).rendered == "1.3.0")
    #expect(BumpVersionCore.nextVersion(current: current, target: .major).rendered == "2.0.0")
    let explicit = try VersionBumpTarget(parsing: "9.8.7")
    #expect(BumpVersionCore.nextVersion(current: current, target: explicit).rendered == "9.8.7")
}

@Test func replaceProjectVersionsUpdatesBothKeys() throws {
    let input = """
    options:
      MARKETING_VERSION: 1.2.3
      CURRENT_PROJECT_VERSION: 1.2.3
    """
    let updated = try BumpVersionCore.replaceProjectVersions(input, version: "1.2.4")
    #expect(updated.contains("MARKETING_VERSION: 1.2.4"))
    #expect(updated.contains("CURRENT_PROJECT_VERSION: 1.2.4"))
}

@Test func replaceReadmeBadgeUpdatesFirstMatch() throws {
    let input = "badge version-1.2.3-blue and version-1.2.3-blue"
    let updated = try BumpVersionCore.replaceReadmeBadge(input, version: "1.2.4")
    #expect(updated == "badge version-1.2.4-blue and version-1.2.3-blue")
}

@Test func insertChangelogEntryInsertsBeforeFirstRelease() throws {
    let input = "# Changelog\n\n## [1.2.3] - 2026-01-01\n\n### Fixed\n- old\n"
    let updated = try BumpVersionCore.insertChangelogEntry(input, version: "1.2.4", entryDate: "2026-08-08")
    #expect(updated.contains("## [1.2.4] - 2026-08-08"))
    #expect(updated.hasPrefix("# Changelog\n\n## [1.2.4]"))
}
