import Foundation
import ModelSwitchboardCore
import Observation

/// Weekly GitHub release check. Advisory only: fetch failures, junk tags,
/// and dev builds stay silent instead of painting error UI.
@MainActor
@Observable
final class AppUpdateStatus {
    struct Release: Equatable, Sendable {
        /// Latest version without the `v` tag prefix, e.g. `2.1.0`.
        let version: String
        let url: URL
    }

    static let releasesURL = URL(string: "https://github.com/AdityaVG13/Model-Switchboard/releases/latest")!
    static let apiURL = URL(string: "https://api.github.com/repos/AdityaVG13/Model-Switchboard/releases/latest")!
    static let checkInterval: TimeInterval = 7 * 24 * 3_600
    static let lastCheckKey = "modelswitchboard.appupdate.lastcheck"

    var available: Release?

    private let currentVersion: String
    private let session: URLSession
    private let endpoint: URL
    private let defaults: UserDefaults

    init(
        currentVersion: String,
        session: URLSession = .shared,
        endpoint: URL = AppUpdateStatus.apiURL,
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.session = session
        self.endpoint = endpoint
        self.defaults = defaults
    }

    var isDue: Bool {
        guard let last = defaults.object(forKey: Self.lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= Self.checkInterval
    }

    func checkIfDue() async {
        guard Self.dottedNumeric(currentVersion) != nil else { return }
        guard isDue else { return }
        // Attempt counts even on failure: an offline Mac must not retry on
        // every panel open for a week.
        defaults.set(Date(), forKey: Self.lastCheckKey)
        available = await fetchRelease()
    }

    private func fetchRelease() async -> Release? {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("ModelSwitchboard-UpdateCheck", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let tag = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let rawTag = tag["tag_name"] as? String,
            let latest = Self.dottedNumeric(strippingTagPrefix(rawTag)),
            let current = Self.dottedNumeric(currentVersion),
            RemoteAgentVersion.compare(current, latest) == .orderedAscending
        else { return nil }
        return Release(version: latest, url: Self.releasesURL)
    }

    private func strippingTagPrefix(_ tag: String) -> String {
        let trimmed = tag.trimmed
        return trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
    }

    /// Numeric dotted versions only (`2.0.0`); `dev` and junk stay silent.
    static func dottedNumeric(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty,
            trimmed.split(separator: ".").allSatisfy({ Int($0) != nil })
        else { return nil }
        return trimmed
    }
}
