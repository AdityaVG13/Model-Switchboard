import Foundation

/// Doctor-specific view over the shared profile snapshot.
///
/// The doctor payload's per-profile rows are role-flagged views over
/// `ModelProfileStatus` - the same snapshot type the status endpoint serves -
/// plus the findings only doctor computes (`errors`/`warnings`). The former
/// 10-field twin (profile/displayName/runtime/runtimeLabel/runtimeTags/
/// launchMode/running/ready/pid/baseURL) is deleted: each of those facts now
/// lives in `status` exactly once (L12).
public struct ProfileDiagnostic: Codable, Equatable, Identifiable, Sendable {
    /// The shared profile snapshot; single owner of every status fact.
    public let status: ModelProfileStatus
    /// Doctor-specific findings for this profile.
    public let errors: [String]
    public let warnings: [String]

    public var id: String { status.profile }

    // Role-flagged pass-throughs used by the diagnostics UI (cards, error
    // copy, sorting). Computed, not stored - they cannot diverge from the
    // snapshot.
    public var profile: String { status.profile }
    public var displayName: String { status.displayName }
    public var baseURL: String { status.baseURL }

    public init(status: ModelProfileStatus, errors: [String], warnings: [String]) {
        self.status = status
        self.errors = errors
        self.warnings = warnings
    }
}
