import Foundation

public struct ProfileDiagnostic: Codable, Equatable, Identifiable, Sendable {
    public let profile: String
    public let displayName: String
    public let runtime: String
    public let runtimeLabel: String?
    public let runtimeTags: [String]?
    public let launchMode: String?
    public let errors: [String]
    public let warnings: [String]
    public let running: Bool
    public let ready: Bool
    public let pid: Int?
    public let baseURL: String

    public var id: String { profile }

    public init(
        profile: String,
        displayName: String,
        runtime: String,
        runtimeLabel: String? = nil,
        runtimeTags: [String]? = nil,
        launchMode: String? = nil,
        errors: [String],
        warnings: [String],
        running: Bool,
        ready: Bool,
        pid: Int?,
        baseURL: String
    ) {
        self.profile = profile
        self.displayName = displayName
        self.runtime = runtime
        self.runtimeLabel = runtimeLabel
        self.runtimeTags = runtimeTags
        self.launchMode = launchMode
        self.errors = errors
        self.warnings = warnings
        self.running = running
        self.ready = ready
        self.pid = pid
        self.baseURL = baseURL
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case displayName = "display_name"
        case runtime
        case runtimeLabel = "runtime_label"
        case runtimeTags = "runtime_tags"
        case launchMode = "launch_mode"
        case errors
        case warnings
        case running
        case ready
        case pid
        case baseURL = "base_url"
    }
}
