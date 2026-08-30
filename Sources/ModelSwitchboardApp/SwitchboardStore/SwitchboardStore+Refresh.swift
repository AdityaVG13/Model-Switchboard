import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
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
        if refreshState == .refreshing {
            needsRefreshAgain = true
            return
        }
        needsRefreshAgain = false
        let previousState = refreshState
        refreshState = .refreshing
        defer {
            if refreshState == .refreshing {
                refreshState = previousState
            }
            if needsRefreshAgain {
                needsRefreshAgain = false
                Task { await self.refresh() }
            }
        }
        do {
            let client = try self.client
            async let statusTask = client.fetchStatus()
            async let doctorTask = client.fetchDoctorReport()
            let payload = try await statusTask
            apply(payload: payload)
            cachePayload(payload, context: "refresh")
            // Refresh itself holds isRefreshing - allow the post-refresh probe.
            await probeLoopbackEndpointsIfNeeded(allowDuringRefresh: true)
            if let report = try? await doctorTask {
                apply(doctorReport: report)
            }
            refreshState = .refreshed
            lastUpdated = Date()
        } catch {
            if isBenignCancellation(error) { return }
            if statuses.isEmpty, let cached = cachedStateLoader() {
                apply(payload: cached.payload)
                lastUpdated = cached.cachedAt
                // A sticky gateway diagnostic (blocked before this refresh) keeps
                // the slot: it outranks the cache-fallback copy and must never be
                // re-derived from message text. Otherwise the fallback is
                // recorded as the structured .failedShowingCached provenance.
                if case .blocked = previousState { return }
                refreshState = .failedShowingCached(message: "Controller unavailable. Showing cached state.")
                return
            }
            if case .blocked = previousState { return }
            refreshState = .failed(message: Self.userFacingErrorDescription(for: error))
        }
    }

    func refreshDoctorReport() async {
        if isRunningControllerDoctor { return }
        isRunningControllerDoctor = true
        defer { isRunningControllerDoctor = false }

        do {
            let report = try await client.fetchDoctorReport()
            apply(doctorReport: report)
            refreshState = .refreshed
        } catch {
            if isBenignCancellation(error) { return }
            recordRefreshFailure(error)
        }
    }

    func applyBootstrapDiagnostic(_ message: String?) {
        if let message {
            refreshState = .blocked(message: message)
        } else if case .blocked = refreshState {
            // Clearing the sticky diagnostic leaves any transient failure intact.
            refreshState = .idle
        }
    }

    /// Drop in-memory statuses before a force-update so the board cannot keep
    /// showing ports/models that the remote agent no longer (or never) owns.
    func discardLiveStatusForForceUpdate() {
        statuses = []
        lastUpdated = nil
        refreshState = .idle
        needsRefreshAgain = false
    }
}
