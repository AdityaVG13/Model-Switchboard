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
        static let statusStaleThresholdSeconds: TimeInterval = 45
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

    enum ProfileBadgeState: Equatable {
        case pending(String)
        case running
        case stale
        case notRunning
    }

    typealias LoopbackEndpointProbe = ([ModelProfileStatus]) async -> Set<String>
    typealias ControllerClientFactory = (String) throws -> ControllerClient
    typealias CachePayloadWriter = @MainActor (ControllerStatusPayload, String) -> Void

    var controllerBaseURL: String
    let features: AppFeatures
    var statuses: [ModelProfileStatus] = []
    var benchmark: BenchmarkStatus?
    var doctorReport: DoctorReport?
    var profileDiagnostics: [ProfileDiagnostic] = []
    var integrations: [ControllerIntegration] = []
    var profilesDirectory: String?
    var controllerRoot: String?
    var lastError: String?
    var isRefreshing = false
    var isRunningControllerDoctor = false
    var lastUpdated: Date?
    var pendingProfileActions: [String: String] = [:]
    var pendingGlobalActions: Set<String> = []
    var pendingIntegrationActions: Set<String> = []
    var lastActiveProfiles: [String] = []
    var lastBenchmarkStartedAt: Date?
    var activeBenchmarkProfiles: [String] = []

    var refreshTask: Task<Void, Never>?
    var loopbackEndpointProbeTask: Task<Void, Never>?
    var loopbackEndpointProbeSession: URLSession?
    var loopbackEndpointProbeFastUntil: Date
    var loopbackEndpointProbeSuppressedUntil: Date?
    let usesCustomLoopbackEndpointProbe: Bool
    let loopbackEndpointProbe: LoopbackEndpointProbe
    let controllerClientFactory: ControllerClientFactory
    let cachePayloadWriter: CachePayloadWriter
    static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")

    init(
        controllerBaseURL: String,
        features: AppFeatures = .current,
        autoStartRefresh: Bool = true,
        loopbackEndpointProbe: LoopbackEndpointProbe? = nil,
        controllerClientFactory: @escaping ControllerClientFactory = { try ControllerClient(baseURLString: $0) },
        cachePayloadWriter: CachePayloadWriter? = nil
    ) {
        self.controllerBaseURL = controllerBaseURL
        self.features = features
        self.loopbackEndpointProbeFastUntil = Date().addingTimeInterval(Constants.loopbackEndpointProbeFastWindowSeconds)
        self.usesCustomLoopbackEndpointProbe = loopbackEndpointProbe != nil
        self.loopbackEndpointProbe = loopbackEndpointProbe ?? { _ in [] }
        self.controllerClientFactory = controllerClientFactory
        self.cachePayloadWriter = cachePayloadWriter ?? Self.writeCachePayload
        loadLastActiveProfiles()
        loadBenchmarkCooldownState()
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
        DashboardSummary(payload: currentPayload)
    }

    var displayedRunningProfiles: Int {
        displayedRunningProfiles(relativeTo: .now)
    }

    var displayedReadyProfiles: Int {
        displayedReadyProfiles(relativeTo: .now)
    }

    var sortedStatuses: [ModelProfileStatus] {
        statuses.sorted(by: ModelProfileStatus.compareForDisplay)
    }

    var menuBarHelp: String {
        menuBarHelp(relativeTo: .now)
    }

    var autoRefreshPolicy: AutoRefreshPolicy {
        AutoRefreshPolicy(
            payload: currentPayload,
            hasPendingActions: !pendingProfileActions.isEmpty ||
                !pendingGlobalActions.isEmpty ||
                !pendingIntegrationActions.isEmpty
        )
    }

    var client: ControllerClient {
        get throws { try controllerClientFactory(controllerBaseURL) }
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
