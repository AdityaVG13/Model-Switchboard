import AppKit
import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

@MainActor
@Observable
final class SwitchboardStore {
    enum Constants {
        static let lastActiveProfilesKey = "modelswitchboard.last-active-profiles"
        static let benchmarkCooldownKey = "modelswitchboard.last-benchmark-started-at"
        static let benchmarkCooldownSeconds: TimeInterval = 300
        static let autoBenchmarkedProfilesKey = "modelswitchboard.auto-benchmarked-profiles"
        static let statusStaleThresholdSeconds: TimeInterval = 900 // > AutoRefreshPolicy.idleInterval (600)
        static let loopbackEndpointProbeFastIntervalSeconds: TimeInterval = 2
        static let loopbackEndpointProbeSteadyIntervalSeconds: TimeInterval = 5
        static let loopbackEndpointProbeIdleIntervalSeconds: TimeInterval = 15
        static let loopbackEndpointProbeSuppressionSeconds: TimeInterval = 4
        static let loopbackEndpointProbeFastWindowSeconds: TimeInterval = 30
        static let loopbackEndpointProbeTimeoutSeconds: TimeInterval = 1
        static let stopVerificationTimeoutSeconds: TimeInterval = 10
        static let stopVerificationPollSeconds: TimeInterval = 0.5
    }

    enum StatusFreshness: Equatable {
        case fresh
        case stale
        case cached
        case error
    }

    /// Single source of truth for the refresh lifecycle and the store's ONE error
    /// slot. Replaces the parallel `isRefreshing` boolean + `lastError` /
    /// `bootstrapDiagnostic` string slots: refreshing-while-failed, two errors at
    /// once, and stale-vs-cached-vs-blocked ambiguity are all unrepresentable now.
    enum RefreshState: Equatable {
        /// No refresh has completed yet (initial store, or after a force-update discard).
        case idle
        /// A refresh is in flight.
        case refreshing
        /// The last refresh (or successful action) completed; freshness is
        /// time-derived from `lastUpdated`.
        case refreshed
        /// The last attempt failed. `message` is user-facing; the board may still
        /// hold stale data (freshness falls back to .stale/.error by statuses).
        case failed(message: String)
        /// A refresh failed and the board is showing the cached payload. The
        /// "cached" provenance is this case — never re-derived from message text.
        case failedShowingCached(message: String)
        /// Sticky gateway-level diagnostic (e.g. tunnel down). Refresh failures
        /// must not clobber it; only a success (or a discard) clears it.
        case blocked(message: String)

        /// The user-facing message carried by any failing case.
        var message: String? {
            switch self {
            case .failed(let message), .failedShowingCached(let message), .blocked(let message):
                return message
            case .idle, .refreshing, .refreshed:
                return nil
            }
        }
    }

    /// A pending per-profile action. The case is the identity; `label` is the
    /// display token shown in the UI (kept byte-stable: hero copy uppercases it).
    enum ProfileAction: String, Equatable, Hashable {
        case activating, starting, stopping, restarting

        var label: String {
            switch self {
            case .activating: "ACTIVATING"
            case .starting: "STARTING"
            case .stopping: "STOPPING"
            case .restarting: "RESTARTING"
            }
        }

        /// User-facing action name for error copy ("Start", "Stop", …).
        var displayName: String {
            switch self {
            case .activating: "Activate"
            case .starting: "Start"
            case .stopping: "Stop"
            case .restarting: "Restart"
            }
        }
    }

    /// A pending global action. Benchmarks carry their target as data instead of
    /// encoding it in a `bench-<profile>` string that callers prefix-sniff.
    enum GlobalAction: Equatable, Hashable {
        case stopAll
        case reopenLastActive
        case benchmarkAll
        case benchmarkSelected
        case benchmark(profile: String)

        var isBenchmark: Bool {
            switch self {
            case .benchmarkAll, .benchmarkSelected, .benchmark: true
            case .stopAll, .reopenLastActive: false
            }
        }
    }

    enum ProfileBadgeState: Equatable {
        case pending(String)
        case running
        case stale
        case notRunning
    }

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

    @ObservationIgnored private var sortedStatusesCache: [ModelProfileStatus]?

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
        loadLastActiveProfiles()
        loadBenchmarkCooldownState()
        loadAutoBenchmarkedProfiles()
        loadCachedState()
        if autoStartRefresh {
            startAutoRefresh()
        }
    }

    var currentPayload: ControllerStatusPayload {
        ControllerStatusPayload(
            statuses: statuses,
            benchmark: benchmark,
            integrations: integrations,
            profilesDirectory: profilesDirectory,
            controllerRoot: controllerRoot
        )
    }

    var summary: DashboardSummary {
        DashboardSummary(counts: ProfileRuntimeCounts(statuses: statuses), benchmark: benchmark)
    }

    var displayedRunningProfiles: Int {
        displayedRunningProfiles(relativeTo: .now)
    }

    var displayedReadyProfiles: Int {
        displayedReadyProfiles(relativeTo: .now)
    }

    var sortedStatuses: [ModelProfileStatus] {
        // Read `statuses` first so observers of `sortedStatuses` are tracked against it
        // even on a cache hit; the cache itself is @ObservationIgnored so filling it
        // during a SwiftUI body evaluation does not invalidate the in-flight render.
        let statuses = self.statuses
        if let sortedStatusesCache { return sortedStatusesCache }
        let sorted = statuses.filter(\.isBoardVisible).sortedForDisplay()
        sortedStatusesCache = sorted
        return sorted
    }

    var menuBarHelp: String {
        menuBarHelp(relativeTo: .now)
    }

    var autoRefreshPolicy: AutoRefreshPolicy {
        AutoRefreshPolicy(
            payload: currentPayload,
            hasPendingActions: hasPendingActions
        )
    }

    /// Derived view convenience: the user-facing error message when the refresh
    /// state holds one. Read-only projection of `refreshState` — not a slot.
    var lastError: String? {
        refreshState.message
    }

    /// Derived view convenience: a refresh is in flight.
    var isRefreshing: Bool {
        refreshState == .refreshing
    }

    var hasPendingActions: Bool {
        !pendingProfileActions.isEmpty ||
            !pendingGlobalActions.isEmpty ||
            !pendingIntegrationActions.isEmpty
    }

    var client: ControllerClient {
        get throws {
            let token = controllerAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return try controllerClientFactory(controllerBaseURL, token.isEmpty ? nil : token)
        }
    }

    var diagnosticsNeedingAttention: [ProfileDiagnostic] {
        profileDiagnostics.filter { !$0.errors.isEmpty || !$0.warnings.isEmpty }
    }

    var loopbackEndpointProbeCandidates: [ModelProfileStatus] {
        statuses.filter { status in
            status.running &&
                status.ready &&
                status.usesLoopbackEndpoint &&
                pendingProfileActions[status.profile] == nil
        }
    }
}
