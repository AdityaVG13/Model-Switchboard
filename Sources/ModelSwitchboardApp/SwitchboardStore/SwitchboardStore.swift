import AppKit
import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

@MainActor
@Observable
final class SwitchboardStore {
    typealias LoopbackEndpointProbe = ([ModelProfileStatus]) async -> Set<String>
    typealias ControllerClientFactory = (String, String?) throws -> ControllerClient
    typealias CachePayloadWriter = @MainActor (ControllerStatusPayload, String) -> Void
    typealias CachedStateLoader = () -> CachedControllerStatusPayload?

    var controllerBaseURL: String
    var controllerAuthToken: String
    let features: AppFeatures
    /// Which gateway this store fronts. Remote stores skip local-only behavior:
    /// the loopback endpoint probe (remote profiles report loopback URLs that
    /// are only loopback *on the remote host*) and the shared status cache.
    let gateway: GatewayContext
    var statuses: [ModelProfileStatus] = [] {
        didSet { sortedStatusesCache = nil }
    }
    var benchmark: BenchmarkStatus?
    var doctorReport: DoctorReport?
    var profileDiagnostics: [ProfileDiagnostic] = []
    var integrations: [ControllerIntegration] = []
    var profilesDirectory: String?
    var controllerRoot: String?
    /// Refresh lifecycle + single error slot (see `RefreshState`).
    var refreshState: RefreshState = .idle
    /// Last refresh/action failed on DNS / connection refused / no route. Drives
    /// the recovering auto-refresh cadence so a post-reboot Tailscale or
    /// LaunchAgent delay does not sit on the idle 10-minute interval.
    var isRecoveringFromTransportFailure = false
    /// Coalesce overlapping refresh() calls into one follow-up instead of dropping them.
    var needsRefreshAgain = false
    var isRunningControllerDoctor = false
    var lastUpdated: Date?
    var pendingProfileActions: [String: ProfileAction] = [:]
    var pendingGlobalActions: Set<GlobalAction> = []
    var pendingIntegrationActions: Set<String> = []
    var lastActiveProfiles: [String] = []
    var lastBenchmarkStartedAt: Date?
    var activeBenchmarkProfiles: [String] = []
    /// Profiles that already received the one-shot auto-benchmark for this store.
    var autoBenchmarkedProfiles: Set<String> = []

    @ObservationIgnored var sortedStatusesCache: [ModelProfileStatus]?

    var refreshTask: Task<Void, Never>?
    var loopbackEndpointProbeTask: Task<Void, Never>?
    var loopbackEndpointProbeSession: URLSession?
    var loopbackEndpointProbeFastUntil: Date
    var loopbackEndpointProbeSuppressedUntil: Date?
    let usesCustomLoopbackEndpointProbe: Bool
    let loopbackEndpointProbe: LoopbackEndpointProbe
    let controllerClientFactory: ControllerClientFactory
    let cachePayloadWriter: CachePayloadWriter
    let cachedStateLoader: CachedStateLoader
    static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")

    init(
        controllerBaseURL: String,
        controllerAuthToken: String = "",
        features: AppFeatures = .current,
        gateway: GatewayContext = .local,
        autoStartRefresh: Bool = true,
        loopbackEndpointProbe: LoopbackEndpointProbe? = nil,
        controllerClientFactory: @escaping ControllerClientFactory = { try ControllerClient(baseURLString: $0, authToken: $1) },
        cachePayloadWriter: CachePayloadWriter? = nil,
        cachedStateLoader: CachedStateLoader? = nil
    ) {
        self.controllerBaseURL = controllerBaseURL
        self.controllerAuthToken = controllerAuthToken
        self.features = features
        self.gateway = gateway
        self.loopbackEndpointProbeFastUntil = Date().addingTimeInterval(Constants.loopbackEndpointProbeFastWindowSeconds)
        self.usesCustomLoopbackEndpointProbe = loopbackEndpointProbe != nil
        self.loopbackEndpointProbe = loopbackEndpointProbe ?? { _ in [] }
        self.controllerClientFactory = controllerClientFactory
        // Remote stores default to no cache I/O: the single cache file feeds the
        // widget and local-controller migration, and must only hold local state.
        self.cachePayloadWriter = cachePayloadWriter ?? (gateway.isLocal ? Self.writeCachePayload : Self.discardCachePayload)
        self.cachedStateLoader = cachedStateLoader ?? (gateway.isLocal ? { ControllerStatusCache.load() } : { nil })
        loadPersistedState()
        if autoStartRefresh {
            startAutoRefresh()
        }
    }
}
