import AppKit
import Foundation
import Observation
import ModelSwitchboardCore

@MainActor
@Observable
final class SwitchboardStore {
    var controllerBaseURL: String
    var statuses: [ModelProfileStatus] = []
    var benchmark: BenchmarkStatus?
    var integrations: [ControllerIntegration] = []
    var profilesDirectory: String?
    var controllerRoot: String?
    var lastError: String?
    var isRefreshing = false
    var lastUpdated: Date?
    var pendingProfileActions: [String: String] = [:]
    var pendingGlobalActions: Set<String> = []
    var pendingIntegrationActions: Set<String> = []

    private var refreshTask: Task<Void, Never>?

    init(controllerBaseURL: String) {
        self.controllerBaseURL = controllerBaseURL
        loadCachedState()
    }

    var summary: DashboardSummary {
        DashboardSummary(
            payload: ControllerStatusPayload(
                statuses: statuses,
                benchmark: benchmark,
                integrations: integrations,
                profilesDirectory: profilesDirectory,
                controllerRoot: controllerRoot
            )
        )
    }

    var sortedStatuses: [ModelProfileStatus] {
        statuses.sorted { lhs, rhs in
            if lhs.ready != rhs.ready { return lhs.ready && !rhs.ready }
            if lhs.running != rhs.running { return lhs.running && !rhs.running }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var menuBarHelp: String {
        let running = sortedStatuses.filter(\.running)
        guard !running.isEmpty else {
            return "No local models running"
        }
        return "Running: " + running.map(\.displayName).joined(separator: ", ")
    }

    func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                let interval = autoRefreshPolicy.interval
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let payload = try await client.fetchStatus()
            apply(payload: payload)
            try? ControllerStatusCache.write(payload)
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
        guard pendingIntegrationActions.insert(integration.id).inserted else { return }
        defer { pendingIntegrationActions.remove(integration.id) }
        await run { try await $0.runIntegration(id: integration.id, action: action) }
    }

    func stopAll() async {
        guard pendingGlobalActions.insert("stop-all").inserted else { return }
        defer { pendingGlobalActions.remove("stop-all") }
        statuses = statuses.map { $0.updating(running: false, ready: false) }
        await run { try await $0.stopAll() }
    }

    func quickBenchmark(_ profiles: [String]? = nil) async {
        let key = profiles == nil ? "bench-all" : "bench-selected"
        guard pendingGlobalActions.insert(key).inserted else { return }
        defer { pendingGlobalActions.remove(key) }
        await run { try await $0.quickBenchmark(profiles: profiles) }
    }

    func openDashboard() {
        guard let url = URL(string: controllerBaseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLatestBenchmark() {
        guard let path = benchmark?.latest?.markdownPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func openProfilesDirectory() {
        guard let profilesDirectory else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: profilesDirectory))
    }

    func openControllerRoot() {
        guard let target = resolvedControllerRoot else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }

    func openEndpoint(_ profile: ModelProfileStatus) {
        guard let url = URL(string: profile.baseURL + "/models") else { return }
        NSWorkspace.shared.open(url)
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

    var autoRefreshPolicy: AutoRefreshPolicy {
        AutoRefreshPolicy(
            payload: ControllerStatusPayload(
                statuses: statuses,
                benchmark: benchmark,
                integrations: integrations,
                profilesDirectory: profilesDirectory,
                controllerRoot: controllerRoot
            ),
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

    private func run(_ action: @escaping (ControllerClient) async throws -> ControllerActionResponse) async {
        do {
            let client = try self.client
            let response = try await action(client)
            if let statuses = response.statuses { self.statuses = statuses }
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
        benchmark = payload.benchmark
        integrations = payload.integrations
        profilesDirectory = payload.profilesDirectory
        controllerRoot = payload.controllerRoot
    }

    private func loadCachedState() {
        guard let cached = ControllerStatusCache.load() else { return }
        apply(payload: cached.payload)
        lastUpdated = cached.cachedAt
    }

    private func cacheCurrentState() {
        try? ControllerStatusCache.write(
            ControllerStatusPayload(
                statuses: statuses,
                benchmark: benchmark,
                integrations: integrations,
                profilesDirectory: profilesDirectory,
                controllerRoot: controllerRoot
            )
        )
    }

    private func isBenignCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
