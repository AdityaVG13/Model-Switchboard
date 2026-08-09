import Foundation
import Testing
@testable import BumpVersionCore

@Test func nextVersionIncrementsPatchMinorMajor() throws {
    let current = try SemanticVersion(parsing: "1.2.3")
    #expect(BumpVersionCore.nextVersion(current: current, target: .patch).rendered == "1.2.4")
    #expect(BumpVersionCore.nextVersion(current: current, target: .minor).rendered == "1.3.0")
    #expect(BumpVersionCore.nextVersion(current: current, target: .major).rendered == "2.0.0")
    let explicit = try VersionBumpTarget(parsing: "9.8.7")
    #expect(BumpVersionCore.nextVersion(current: current, target: explicit).rendered == "9.8.7")
}

@Test func replaceProjectVersionsUpdatesBothKeys() throws {
    let input = """
    settings:
      base:
        MARKETING_VERSION: 1.2.3
        CURRENT_PROJECT_VERSION: 1.2.3
    """
    let updated = try BumpVersionCore.replaceProjectVersions(input, version: "4.5.6")
    #expect(updated.contains("MARKETING_VERSION: 4.5.6"))
    #expect(updated.contains("CURRENT_PROJECT_VERSION: 4.5.6"))
}

@Test func replaceReadmeBadgeReplacesFirstOnly() throws {
    let input = "badge version-1.2.3-blue and version-1.2.3-blue again"
    let updated = try BumpVersionCore.replaceReadmeBadge(input, version: "4.5.6")
    #expect(updated == "badge version-4.5.6-blue and version-1.2.3-blue again")
}

@Test func insertChangelogEntryBeforeFirstRelease() throws {
    let input = """
    # Changelog

    ## [1.0.0] - 2026-01-01

    ### Added
    - ship
    """
    let updated = try BumpVersionCore.insertChangelogEntry(input, version: "1.1.0", entryDate: "2026-08-08")
    #expect(updated.contains("## [1.1.0] - 2026-08-08"))
    let first = updated.range(of: "## [1.1.0]")!
    let second = updated.range(of: "## [1.0.0]")!
    #expect(first.lowerBound < second.lowerBound)
}

@Test func insertChangelogEntryRejectsDuplicate() {
    let input = "## [1.1.0] - already\n"
    #expect(throws: BumpVersionError.changelogAlreadyContains("## [1.1.0]")) {
        try BumpVersionCore.insertChangelogEntry(input, version: "1.1.0", entryDate: "2026-08-08")
    }
}
