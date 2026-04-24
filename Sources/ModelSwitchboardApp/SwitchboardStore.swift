import AppKit
import Foundation
import Observation
import OSLog
import ModelSwitchboardCore

@MainActor
@Observable
final class SwitchboardStore {
    private enum Constants {
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

    private var refreshTask: Task<Void, Never>?
    private var loopbackEndpointProbeTask: Task<Void, Never>?
    private var loopbackEndpointProbeSession: URLSession?
    private var loopbackEndpointProbeFastUntil: Date
    private var loopbackEndpointProbeSuppressedUntil: Date?
    private let usesCustomLoopbackEndpointProbe: Bool
    private let loopbackEndpointProbe: LoopbackEndpointProbe
    private static let logger = Logger(subsystem: "io.modelswitchboard.app", category: "switchboard-store")

    init(
        controllerBaseURL: String,
        features: AppFeatures = .current,
        autoStartRefresh: Bool = true,
        loopbackEndpointProbe: LoopbackEndpointProbe? = nil
    ) {
        self.controllerBaseURL = controllerBaseURL
        self.features = features
        self.loopbackEndpointProbeFastUntil = Date().addingTimeInterval(Constants.loopbackEndpointProbeFastWindowSeconds)
        self.usesCustomLoopbackEndpointProbe = loopbackEndpointProbe != nil
        self.loopbackEndpointProbe = loopbackEndpointProbe ?? { _ in [] }
        loadLastActiveProfiles()
        loadBenchmarkCooldownState()
        loadCachedState()
        if autoStartRefresh {
            startAutoRefresh()
        }
    }

    private var currentPayload: ControllerStatusPayload {
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

    func menuBarHelp(relativeTo now: Date) -> String {
        switch statusFreshness(relativeTo: now) {
        case .cached:
            return "Cached local model state may be stale. Refresh to verify live status."
        case .stale:
            return "Local model status is stale. Refresh to verify live status."
        case .error where !statuses.isEmpty:
            return "Local model status is unavailable. Refresh to verify live status."
        case .error, .fresh:
            let running = sortedStatuses.filter(\.running)
            guard !running.isEmpty else {
                return "No local models running"
            }
            return "Running: " + running.map(\.displayName).joined(separator: ", ")
        }
    }

    func statusFreshness(relativeTo now: Date) -> StatusFreshness {
        if let lastError, !lastError.isEmpty {
            if !statuses.isEmpty {
                if lastError.localizedCaseInsensitiveContains("cached") {
                    return .cached
                }
                return .stale
            }
            return .error
        }

        guard let lastUpdated else {
            return .error
        }

        if now.timeIntervalSince(lastUpdated) > Constants.statusStaleThresholdSeconds {
            return .stale
        }

        return .fresh
    }

    func displayedRunningProfiles(relativeTo now: Date) -> Int {
        statusFreshness(relativeTo: now) == .fresh ? summary.runningProfiles : 0
    }

    func displayedReadyProfiles(relativeTo now: Date) -> Int {
        statusFreshness(relativeTo: now) == .fresh ? summary.readyProfiles : 0
    }

    func profileBadgeState(for profile: ModelProfileStatus, relativeTo now: Date) -> ProfileBadgeState {
        if let pending = pendingLabel(for: profile.profile) {
            return .pending(pending)
        }
        if profile.running && statusFreshness(relativeTo: now) != .fresh {
            return .stale
        }
        return profile.running ? .running : .notRunning
    }

    var canReopenLastActive: Bool {
        features.supportsBenchmarks &&
        !lastActiveProfiles.isEmpty &&
        !pendingGlobalActions.contains("reopen-last") &&
        !statuses.contains(where: \.running) &&
        pendingProfileActions.isEmpty
    }

    var benchmarkCooldownRemaining: TimeInterval {
        guard let lastBenchmarkStartedAt else { return 0 }
        let remaining = Constants.benchmarkCooldownSeconds - Date().timeIntervalSince(lastBenchmarkStartedAt)
        return max(0, remaining)
    }

    var benchmarkCooldownEndsAt: Date? {
        guard let lastBenchmarkStartedAt else { return nil }
        return lastBenchmarkStartedAt.addingTimeInterval(Constants.benchmarkCooldownSeconds)
    }

    var canStartBenchmarkNow: Bool {
        features.supportsBenchmarks &&
        benchmark?.running != true &&
        benchmarkCooldownRemaining <= 0
    }

    var benchmarkCooldownLabel: String? {
        let remaining = benchmarkCooldownRemaining
        guard remaining > 0 else { return nil }
        let seconds = Int(remaining.rounded(.up))
        let minutesPart = seconds / 60
        let secondsPart = seconds % 60
        if minutesPart > 0 {
            return "\(minutesPart)m \(secondsPart)s"
        }
        return "\(secondsPart)s"
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        startLoopbackEndpointProbe()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                let interval = autoRefreshPolicy.interval
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    if isBenignCancellation(error) { break }
                    Self.logger.error("Auto refresh sleep failed: \(String(describing: error), privacy: .public)")
                    break
                }
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        loopbackEndpointProbeTask?.cancel()
        loopbackEndpointProbeTask = nil
        loopbackEndpointProbeSession?.invalidateAndCancel()
        loopbackEndpointProbeSession = nil
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let client = try self.client
            async let statusTask = client.fetchStatus()
            async let doctorTask = client.fetchDoctorReport()
            let payload = try await statusTask
            apply(payload: payload)
            cachePayload(payload, context: "refresh")
            await probeLoopbackEndpointsIfNeeded()
            if let report = try? await doctorTask {
                apply(doctorReport: report)
            }
            lastError = nil
            lastUpdated = Date()
        } catch {
            if isBenignCancellation(error) { return }
            if statuses.isEmpty, let cached = ControllerStatusCache.load() {
                apply(payload: cached.payload)
                lastUpdated = cached.cachedAt
                lastError = "Controller unavailable. Showing cached state."
                return
            }
            lastError = error.localizedDescription
        }
    }

    func refreshDoctorReport() async {
        if isRunningControllerDoctor { return }
        isRunningControllerDoctor = true
        defer { isRunningControllerDoctor = false }

        do {
            let report = try await client.fetchDoctorReport()
            apply(doctorReport: report)
            lastError = nil
        } catch {
            if isBenignCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func activate(_ profile: String) async {
        await runProfileAction(profile, label: "ACTIVATING") {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.activate(profile: profile)
        }
    }

    func start(_ profile: String) async {
        await runProfileAction(profile, label: "STARTING") {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.start(profile: profile)
        }
    }

    func stop(_ profile: String) async {
        await runProfileAction(profile, label: "STOPPING") {
            markProfile(profile, running: false, ready: false)
        } action: {
            try await $0.stop(profile: profile)
        }
    }

    func restart(_ profile: String) async {
        await runProfileAction(profile, label: "RESTARTING") {
            markProfile(profile, running: true, ready: false)
        } action: {
            try await $0.restart(profile: profile)
        }
    }

    func runIntegration(_ integration: ControllerIntegration, action: String = "sync") async {
        guard features.supportsIntegrations else { return }
        guard pendingIntegrationActions.insert(integration.id).inserted else { return }
        defer { pendingIntegrationActions.remove(integration.id) }
        await run { try await $0.runIntegration(id: integration.id, action: action) }
    }

    func stopAll() async {
        guard pendingGlobalActions.insert("stop-all").inserted else { return }
        defer { pendingGlobalActions.remove("stop-all") }
        noteManagedLoopbackTransition()
        rememberLastActiveProfiles(from: statuses)
        statuses = statuses.map { $0.updating(running: false, ready: false) }
        await run { try await $0.stopAll() }
    }

    func quickBenchmark(_ profiles: [String]? = nil) async {
        guard features.supportsBenchmarks else { return }
        if benchmark?.running == true {
            return
        }
        if benchmarkCooldownRemaining > 0 {
            return
        }
        let key: String
        if let profiles, profiles.count == 1, let profile = profiles.first {
            key = "bench-\(profile)"
        } else if profiles == nil {
            key = "bench-all"
        } else {
            key = "bench-selected"
        }
        guard pendingGlobalActions.insert(key).inserted else { return }
        activeBenchmarkProfiles = profiles ?? []
        markBenchmarkStarted()
        defer {
            pendingGlobalActions.remove(key)
        }
        await run { try await $0.quickBenchmark(profiles: profiles) }
    }

    func reopenLastActive() async {
        guard canReopenLastActive else { return }
        let profiles = lastActiveProfiles
        guard pendingGlobalActions.insert("reopen-last").inserted else { return }
        defer { pendingGlobalActions.remove("reopen-last") }
        noteManagedLoopbackTransition()

        for profile in profiles {
            pendingProfileActions[profile] = "STARTING"
            markProfile(profile, running: true, ready: false)
        }

        defer {
            for profile in profiles {
                pendingProfileActions.removeValue(forKey: profile)
            }
        }

        do {
            let client = try self.client
            for profile in profiles {
                _ = try await client.start(profile: profile)
            }
            await refresh()
        } catch {
            if isBenignCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func openProfilesDirectory() {
        guard let profilesDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: profilesDirectory))
    }

    func openControllerRoot() {
        guard let target = resolvedControllerRoot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    func openExampleProfilesDirectory() {
        guard let target = resolvedExampleProfilesDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    var resolvedControllerRoot: String? {
        if let controllerRoot, !controllerRoot.isEmpty {
            return controllerRoot
        }

        guard let profilesDirectory, !profilesDirectory.isEmpty else { return nil }
        return URL(fileURLWithPath: profilesDirectory)
            .deletingLastPathComponent()
            .path
    }

    var resolvedExampleProfilesDirectory: String? {
        let preferredTargets = [
            profilesDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent("examples").path },
            resolvedControllerRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("model-profiles/examples").path },
        ]

        for target in preferredTargets.compactMap({ $0 }) where FileManager.default.fileExists(atPath: target) {
            return target
        }
        return nil
    }

    var autoRefreshPolicy: AutoRefreshPolicy {
        AutoRefreshPolicy(
            payload: currentPayload,
            hasPendingActions: !pendingProfileActions.isEmpty ||
                !pendingGlobalActions.isEmpty ||
                !pendingIntegrationActions.isEmpty
        )
    }

    private var client: ControllerClient {
        get throws { try ControllerClient(baseURLString: controllerBaseURL) }
    }

    func isBusy(profile: String) -> Bool {
        pendingProfileActions[profile] != nil
    }

    func pendingLabel(for profile: String) -> String? {
        pendingProfileActions[profile]
    }

    func isBenchmarkInFlight(for profile: String? = nil) -> Bool {
        if benchmark?.running == true { return true }
        if let profile {
            return pendingGlobalActions.contains("bench-\(profile)") ||
                pendingGlobalActions.contains("bench-selected") ||
                pendingGlobalActions.contains("bench-all")
        }

        if pendingGlobalActions.contains("bench-all") || pendingGlobalActions.contains("bench-selected") {
            return true
        }
        return pendingGlobalActions.contains(where: { $0.hasPrefix("bench-") })
    }

    func shouldProbeLoopbackEndpoints(relativeTo now: Date = .now) -> Bool {
        !loopbackEndpointProbeCandidates.isEmpty && !isLoopbackEndpointProbeSuppressed(relativeTo: now)
    }

    func nextLoopbackEndpointProbeInterval(relativeTo now: Date = .now) -> TimeInterval {
        guard !loopbackEndpointProbeCandidates.isEmpty else {
            return Constants.loopbackEndpointProbeIdleIntervalSeconds
        }
        if let suppressedUntil = loopbackEndpointProbeSuppressedUntil, suppressedUntil > now {
            return max(0.5, suppressedUntil.timeIntervalSince(now))
        }
        if now < loopbackEndpointProbeFastUntil {
            return Constants.loopbackEndpointProbeFastIntervalSeconds
        }
        return Constants.loopbackEndpointProbeSteadyIntervalSeconds
    }

    func armLoopbackEndpointProbeFastWindow(relativeTo now: Date = .now) {
        loopbackEndpointProbeFastUntil = now.addingTimeInterval(Constants.loopbackEndpointProbeFastWindowSeconds)
    }

    func suppressLoopbackEndpointProbe(relativeTo now: Date = .now) {
        loopbackEndpointProbeSuppressedUntil = now.addingTimeInterval(Constants.loopbackEndpointProbeSuppressionSeconds)
    }

    func probeLoopbackEndpointsIfNeeded(relativeTo now: Date = .now) async {
        guard !isRefreshing else { return }
        guard shouldProbeLoopbackEndpoints(relativeTo: now) else { return }

        let candidates = loopbackEndpointProbeCandidates
        guard !candidates.isEmpty else { return }

        let unreachableProfiles: Set<String>
        if usesCustomLoopbackEndpointProbe {
            unreachableProfiles = await loopbackEndpointProbe(candidates)
        } else {
            if loopbackEndpointProbeSession == nil {
                loopbackEndpointProbeSession = Self.makeLoopbackEndpointProbeSession()
            }
            guard let session = loopbackEndpointProbeSession else { return }
            unreachableProfiles = await Self.detectUnreachableLoopbackProfiles(in: candidates, using: session)
        }
        guard !unreachableProfiles.isEmpty else { return }

        statuses = statuses.map { status in
            guard unreachableProfiles.contains(status.profile) else { return status }
            return status.markingEndpointUnavailable()
        }
    }

    private func run(_ action: @escaping (ControllerClient) async throws -> ControllerActionResponse) async {
        do {
            let client = try self.client
            let response = try await action(client)
            if let statuses = response.statuses {
                self.statuses = statuses
                rememberLastActiveProfiles(from: statuses)
            }
            if let benchmark = response.benchmark { self.benchmark = benchmark }
            if let integrations = response.integrations { self.integrations = integrations }
            if let profilesDirectory = response.profilesDirectory { self.profilesDirectory = profilesDirectory }
            if let controllerRoot = response.controllerRoot { self.controllerRoot = controllerRoot }
            cacheCurrentState()
            lastError = nil
            lastUpdated = Date()
            await refresh()
        } catch {
            if isBenignCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    private func runProfileAction(
        _ profile: String,
        label: String,
        optimisticUpdate: () -> Void,
        action: @escaping (ControllerClient) async throws -> ControllerActionResponse
    ) async {
        guard pendingProfileActions[profile] == nil else { return }
        noteManagedLoopbackTransition()
        pendingProfileActions[profile] = label
        optimisticUpdate()
        defer { pendingProfileActions.removeValue(forKey: profile) }
        await run(action)
    }

    private func markProfile(_ profile: String, running: Bool, ready: Bool) {
        statuses = statuses.map { status in
            guard status.profile == profile else { return status }
            return status.updating(running: running, ready: ready)
        }
    }

    private func apply(payload: ControllerStatusPayload) {
        statuses = payload.statuses
        rememberLastActiveProfiles(from: payload.statuses)
        benchmark = features.supportsBenchmarks ? payload.benchmark : nil
        if benchmark?.running == false {
            activeBenchmarkProfiles = []
        }
        integrations = features.supportsIntegrations ? payload.integrations : []
        profilesDirectory = payload.profilesDirectory
        controllerRoot = payload.controllerRoot
    }

    private func apply(doctorReport: DoctorReport) {
        self.doctorReport = doctorReport
        profileDiagnostics = doctorReport.profiles.sorted(by: Self.compareDiagnostics)
    }

    var diagnosticsNeedingAttention: [ProfileDiagnostic] {
        profileDiagnostics.filter { !$0.errors.isEmpty || !$0.warnings.isEmpty }
    }

    private var loopbackEndpointProbeCandidates: [ModelProfileStatus] {
        statuses.filter { status in
            status.running &&
                status.ready &&
                status.usesLoopbackEndpoint &&
                pendingProfileActions[status.profile] == nil
        }
    }

    private func loadCachedState() {
        guard let cached = ControllerStatusCache.load() else { return }
        apply(payload: cached.payload)
        lastUpdated = cached.cachedAt
    }

    private func cacheCurrentState() {
        cachePayload(currentPayload, context: "state")
    }

    private func cachePayload(_ payload: ControllerStatusPayload, context: String) {
        do {
            try ControllerStatusCache.write(payload)
        } catch {
            Self.logger.error("Cache write failed (\(context, privacy: .public)): \(String(describing: error), privacy: .public)")
        }
    }

    private func loadLastActiveProfiles() {
        lastActiveProfiles = UserDefaults.standard.stringArray(forKey: Constants.lastActiveProfilesKey) ?? []
    }

    private func loadBenchmarkCooldownState() {
        guard let timestamp = UserDefaults.standard.object(forKey: Constants.benchmarkCooldownKey) as? TimeInterval else {
            lastBenchmarkStartedAt = nil
            return
        }
        lastBenchmarkStartedAt = Date(timeIntervalSince1970: timestamp)
    }

    private func markBenchmarkStarted() {
        let now = Date()
        lastBenchmarkStartedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Constants.benchmarkCooldownKey)
    }

    private func startLoopbackEndpointProbe() {
        loopbackEndpointProbeTask?.cancel()
        loopbackEndpointProbeSession = loopbackEndpointProbeSession ?? Self.makeLoopbackEndpointProbeSession()
        loopbackEndpointProbeTask = Task { [weak self] in
            guard let self else { return }
            await self.probeLoopbackEndpointsIfNeeded()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.nextLoopbackEndpointProbeInterval()))
                } catch {
                    if isBenignCancellation(error) { break }
                    Self.logger.error("Loopback endpoint probe sleep failed: \(String(describing: error), privacy: .public)")
                    break
                }
                if Task.isCancelled { break }
                await self.probeLoopbackEndpointsIfNeeded()
            }
        }
    }

    private func noteManagedLoopbackTransition(relativeTo now: Date = .now) {
        armLoopbackEndpointProbeFastWindow(relativeTo: now)
        suppressLoopbackEndpointProbe(relativeTo: now)
    }

    private func isLoopbackEndpointProbeSuppressed(relativeTo now: Date) -> Bool {
        if let suppressedUntil = loopbackEndpointProbeSuppressedUntil, suppressedUntil > now {
            return true
        }
        return false
    }

    private func rememberLastActiveProfiles(from sourceStatuses: [ModelProfileStatus]) {
        let runningProfiles = sourceStatuses
            .filter(\.running)
            .map(\.profile)
        guard !runningProfiles.isEmpty else { return }

        var deduplicated: [String] = []
        var seen: Set<String> = []
        for profile in runningProfiles where seen.insert(profile).inserted {
            deduplicated.append(profile)
        }
        lastActiveProfiles = deduplicated
        UserDefaults.standard.set(deduplicated, forKey: Constants.lastActiveProfilesKey)
    }

    private func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    nonisolated private static func makeLoopbackEndpointProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.timeoutIntervalForResource = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    nonisolated private static func detectUnreachableLoopbackProfiles(
        in statuses: [ModelProfileStatus],
        using session: URLSession
    ) async -> Set<String> {
        var unreachableProfiles: Set<String> = []
        for status in statuses {
            guard let request = loopbackProbeRequest(for: status) else { continue }
            do {
                _ = try await session.data(for: request)
            } catch {
                if isLoopbackConnectionRefused(error) {
                    unreachableProfiles.insert(status.profile)
                }
            }
        }
        return unreachableProfiles
    }

    nonisolated private static func loopbackProbeRequest(for status: ModelProfileStatus) -> URLRequest? {
        guard let baseURL = URL(string: status.baseURL) else { return nil }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Constants.loopbackEndpointProbeTimeoutSeconds
        return request
    }

    nonisolated private static func isLoopbackConnectionRefused(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == ECONNREFUSED {
            return true
        }
        return false
    }

    nonisolated private static func compareDiagnostics(lhs: ProfileDiagnostic, rhs: ProfileDiagnostic) -> Bool {
        let lhsSeverity = lhs.errors.isEmpty ? (lhs.warnings.isEmpty ? 0 : 1) : 2
        let rhsSeverity = rhs.errors.isEmpty ? (rhs.warnings.isEmpty ? 0 : 1) : 2
        if lhsSeverity != rhsSeverity { return lhsSeverity > rhsSeverity }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
}

private extension ModelProfileStatus {
    func markingEndpointUnavailable() -> Self {
        Self(
            profile: profile,
            displayName: displayName,
            runtime: runtime,
            host: host,
            port: port,
            baseURL: baseURL,
            requestModel: requestModel,
            serverModelID: serverModelID,
            pid: nil,
            running: false,
            ready: false,
            serverIDs: [],
            rssMB: nil,
            command: command,
            logPath: logPath
        )
    }

    var usesLoopbackEndpoint: Bool {
        if let endpointHost = URL(string: baseURL)?.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return endpointHost == "127.0.0.1" || endpointHost == "localhost" || endpointHost == "::1"
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedHost == "127.0.0.1" || normalizedHost == "localhost" || normalizedHost == "::1"
    }
}
