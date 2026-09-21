import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    nonisolated static func makeLoopbackEndpointProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.timeoutIntervalForResource = Constants.loopbackEndpointProbeTimeoutSeconds
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        // Match remote client / curl --noproxy: never send loopback probes via a proxy.
        configuration.connectionProxyDictionary = [:]
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
}
