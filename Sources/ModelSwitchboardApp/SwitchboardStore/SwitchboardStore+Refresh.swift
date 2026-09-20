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

    func refresh(includeDoctor: Bool = false) async {
        if refreshState.isInFlight {
            needsRefreshAgain = true
            return
        }
        needsRefreshAgain = false
        let previousState = refreshState
        refreshState = previousState.beginningRefresh()
        defer {
            if refreshState.isInFlight {
                refreshState = previousState
            }
            if needsRefreshAgain {
                needsRefreshAgain = false
                Task { await self.refresh(includeDoctor: includeDoctor) }
            }
        }
        do {
            let client = try self.client
            let payload = try await client.fetchStatus()
            apply(payload: payload)
            cachePayload(payload, context: "refresh")
            // Refresh itself holds isRefreshing - allow the post-refresh probe.
            await probeLoopbackEndpointsIfNeeded(allowDuringRefresh: true)
            // Doctor is a second heavy pass on the agent. Auto-refresh only
            // fetches it once (or when the operator asked) so /api/status is
            // not stacked behind /api/doctor on a busy remote.
            if includeDoctor || doctorReport == nil {
                if let report = try? await client.fetchDoctorReport() {
                    apply(doctorReport: report)
                }
            }
            isRecoveringFromTransportFailure = false
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
                if previousState.isBlocked { return }
                noteRecoveringFrom(error)
                refreshState = .failedShowingCached(message: "Controller unavailable. Showing cached state.")
                return
            }
            if previousState.isBlocked { return }
            noteRecoveringFrom(error)
            refreshState = .failed(
                message: Self.userFacingErrorDescription(for: error, isLocal: gateway.isLocal)
            )
        }
    }

    func refreshDoctorReport() async {
        if isRunningControllerDoctor { return }
        isRunningControllerDoctor = true
        defer { isRunningControllerDoctor = false }

        do {
            let report = try await client.fetchDoctorReport()
            apply(doctorReport: report)
            // Doctor success must not wipe a sticky bootstrap block or a
            // status-refresh failure banner (and must not paint "refreshed"
            // while the recovering cadence is still trying status).
            switch refreshState {
            case .blocked, .failed, .failedShowingCached, .refreshing:
                break
            default:
                refreshState = .refreshed
            }
        } catch {
            if isBenignCancellation(error) { return }
            recordRefreshFailure(error)
        }
    }

    func applyBootstrapDiagnostic(_ message: String?) {
        if let message {
            // Keep the 3s recovering cadence. Clearing it here left local
            // LaunchAgent / Tailscale DNS failures on the idle 10-minute
            // poll after the 1.5s bootstrap wait painted `.blocked`.
            isRecoveringFromTransportFailure = true
            refreshState = .blocked(message: message)
        } else if refreshState.isBlocked {
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
        isRecoveringFromTransportFailure = false
        needsRefreshAgain = false
    }
}
