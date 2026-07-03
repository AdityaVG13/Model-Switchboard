import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
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

        var updated = statuses
        for index in updated.indices where unreachableProfiles.contains(updated[index].profile) {
            updated[index] = updated[index].markingEndpointUnavailable()
        }
        statuses = updated
    }

    func startLoopbackEndpointProbe() {
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

    func noteManagedLoopbackTransition(relativeTo now: Date = .now) {
        armLoopbackEndpointProbeFastWindow(relativeTo: now)
        suppressLoopbackEndpointProbe(relativeTo: now)
    }

    func isLoopbackEndpointProbeSuppressed(relativeTo now: Date) -> Bool {
        loopbackEndpointProbeSuppressedUntil.map { $0 > now } ?? false
    }

    nonisolated static func makeLoopbackEndpointProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.timeoutIntervalForResource = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    nonisolated static func detectUnreachableLoopbackProfiles(
        in statuses: [ModelProfileStatus],
        using session: URLSession
    ) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self) { group in
            for status in statuses {
                guard let request = loopbackProbeRequest(for: status) else { continue }
                group.addTask {
                    do {
                        _ = try await session.data(for: request)
                        return (status.profile, false)
                    } catch {
                        return (status.profile, isLoopbackConnectionRefused(error))
                    }
                }
            }

            var unreachableProfiles: Set<String> = []
            for await (profile, unreachable) in group where unreachable {
                unreachableProfiles.insert(profile)
            }
            return unreachableProfiles
        }
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
}

private extension ModelProfileStatus {
    /// `updating(...)` treats nil as "keep current value", so it cannot clear
    /// pid/rssMB. A dead endpoint must drop them explicitly.
    func markingEndpointUnavailable() -> Self {
        Self(
            profile: profile,
            displayName: displayName,
            runtime: runtime,
            runtimeLabel: runtimeLabel,
            runtimeTags: runtimeTags,
            launchMode: launchMode,
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
}
