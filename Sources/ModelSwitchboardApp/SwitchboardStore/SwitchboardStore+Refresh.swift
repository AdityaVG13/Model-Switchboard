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
            bootstrapDiagnostic = nil
            lastUpdated = Date()
        } catch {
            if isBenignCancellation(error) { return }
            if statuses.isEmpty, let cached = ControllerStatusCache.load() {
                apply(payload: cached.payload)
                lastUpdated = cached.cachedAt
                lastError = bootstrapDiagnostic ?? "Controller unavailable. Showing cached state."
                return
            }
            lastError = bootstrapDiagnostic ?? error.localizedDescription
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
            bootstrapDiagnostic = nil
        } catch {
            if isBenignCancellation(error) { return }
            lastError = bootstrapDiagnostic ?? error.localizedDescription
        }
    }

    func applyBootstrapDiagnostic(_ message: String?) {
        bootstrapDiagnostic = message
        if let message {
            lastError = message
        }
    }
}
