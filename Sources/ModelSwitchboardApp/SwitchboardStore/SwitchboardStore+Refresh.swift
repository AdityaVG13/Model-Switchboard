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
        if isRefreshing {
            needsRefreshAgain = true
            return
        }
        isRefreshing = true
        needsRefreshAgain = false
        // Measurement-only; default off. MSW_PERF_PROFILE=1 or MSW_AGENT_PERF=1.
        let perfOn = Self.perfProfileEnabled
        let t0 = perfOn ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            isRefreshing = false
            if perfOn {
                let durationMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                Self.emitPerfSpan(
                    name: "SwitchboardStore.refresh",
                    durationMs: durationMs,
                    extra: "\"n_statuses\":\(statuses.count)"
                )
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
            // Refresh itself holds isRefreshing — allow the post-refresh probe.
            await probeLoopbackEndpointsIfNeeded(allowDuringRefresh: true)
            if let report = try? await doctorTask {
                apply(doctorReport: report)
            }
            lastError = nil
            bootstrapDiagnostic = nil
            lastUpdated = Date()
        } catch {
            if isBenignCancellation(error) { return }
            if statuses.isEmpty, let cached = cachedStateLoader() {
                apply(payload: cached.payload)
                lastUpdated = cached.cachedAt
                lastError = bootstrapDiagnostic ?? "Controller unavailable. Showing cached state."
                return
            }
            lastError = bootstrapDiagnostic ?? Self.userFacingErrorDescription(for: error)
        }
    }

    /// Env-gated profiling (measurement only). See Tests/artifacts/perf/.../INSTRUMENTATION.md
    private static var perfProfileEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        for key in ["MSW_PERF_PROFILE", "MSW_AGENT_PERF"] {
            if let raw = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               ["1", "true", "yes", "on"].contains(raw) {
                return true
            }
        }
        return false
    }

    private static func emitPerfSpan(name: String, durationMs: Double, extra: String = "") {
        let extras = extra.isEmpty ? "" : ",\(extra)"
        let line = String(
            format: "perf.profile.span_summary {\"span\":\"%@\",\"duration_ms\":%.3f%@}\n",
            name,
            durationMs,
            extras
        )
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
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
            lastError = bootstrapDiagnostic ?? Self.userFacingErrorDescription(for: error)
        }
    }

    func applyBootstrapDiagnostic(_ message: String?) {
        bootstrapDiagnostic = message
        if let message {
            lastError = message
        }
    }

    /// Drop in-memory statuses before a force-update so the board cannot keep
    /// showing ports/models that the remote agent no longer (or never) owns.
    func discardLiveStatusForForceUpdate() {
        statuses = []
        lastUpdated = nil
        lastError = nil
        bootstrapDiagnostic = nil
        needsRefreshAgain = false
    }
}
