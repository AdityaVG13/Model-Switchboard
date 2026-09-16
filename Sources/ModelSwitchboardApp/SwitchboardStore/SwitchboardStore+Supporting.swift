import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// Last-active names that still exist as board-visible rows. Ghosts and
    /// hidden discovery listeners are dropped so Reopen cannot POST `start`
    /// for names the controller will 404.
    var reopenableLastActiveProfiles: [String] {
        lastActiveProfiles.filter { name in
            sortedStatuses.contains { $0.profile == name }
        }
    }

    var canReopenLastActive: Bool {
        features.supportsBenchmarks &&
        !reopenableLastActiveProfiles.isEmpty &&
        !pendingGlobalActions.contains(.reopenLastActive) &&
        !sortedStatuses.contains(where: \.running) &&
        pendingProfileActions.isEmpty
    }

    var benchmarkCooldownRemaining: TimeInterval {
        guard let lastBenchmarkStartedAt else { return 0 }
        return max(0, Constants.benchmarkCooldownSeconds - Date().timeIntervalSince(lastBenchmarkStartedAt))
    }

    var benchmarkCooldownEndsAt: Date? {
        lastBenchmarkStartedAt?.addingTimeInterval(Constants.benchmarkCooldownSeconds)
    }

    var canStartBenchmarkNow: Bool {
        features.supportsBenchmarks && benchmark?.running != true && benchmarkCooldownRemaining <= 0
    }

    var benchmarkCooldownLabel: String? {
        DurationFormatting.compactCountdown(remaining: benchmarkCooldownRemaining)
    }

    func markBenchmarkStarted() {
        let now = Date()
        lastBenchmarkStartedAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: benchmarkCooldownDefaultsKey)
    }

    func openProfilesDirectory() {
        let url = profilesDirectoryToReveal
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        seedBundledExampleProfilesIfNeeded(in: url)
        revealInFinder(url)
    }

    func openControllerRoot() {
        let url = controllerRootToReveal
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        revealInFinder(url)
    }

    func openExampleProfilesDirectory() {
        let profiles = profilesDirectoryToReveal
        try? FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        seedBundledExampleProfilesIfNeeded(in: profiles)
        let examples = exampleProfilesDirectoryToReveal
        if FileManager.default.fileExists(atPath: examples.path) {
            revealInFinder(examples)
        } else {
            revealInFinder(profiles)
        }
    }

    /// Reveals a folder in Finder and brings Finder to the front. `NSWorkspace.open(_:)`
    /// launches Finder but leaves it behind the app; `activateFileViewerSelecting` reveals
    /// the item in a focused window, fixing the "folder opens behind the app" behaviour.
    private func revealInFinder(_ url: URL) {
        let directory = (url.pathExtension.isEmpty || hasDirectoryPath(url))
            ? url
            : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private func hasDirectoryPath(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// First-run Finder open should include the example templates the docs tell
    /// people to copy. Bootstrap usually seeds them; this covers the race
    /// where Open Profiles Folder runs before the LaunchAgent copy finishes.
    private func seedBundledExampleProfilesIfNeeded(in profiles: URL) {
        let examples = profiles.appendingPathComponent("examples", isDirectory: true)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: examples.path) else { return }
        guard
            let bundled = Bundle.main.resourceURL?
                .appendingPathComponent("ControllerSupport/model-profiles/examples", isDirectory: true),
            fileManager.fileExists(atPath: bundled.path)
        else { return }
        try? fileManager.copyItem(at: bundled, to: examples)
    }

    /// Live folder if the controller has reported one; otherwise the embedded
    /// controller's Application Support path so first-run Open Profiles Folder
    /// is not a no-op while status is still coming up.
    var profilesDirectoryToReveal: URL {
        let trimmed = profilesDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return URL(fileURLWithPath: trimmed, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/ModelSwitchboard/Controller/model-profiles",
                isDirectory: true
            )
    }

    var controllerRootToReveal: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/ModelSwitchboard/Controller",
                isDirectory: true
            )
    }

    var exampleProfilesDirectoryToReveal: URL {
        profilesDirectoryToReveal.appendingPathComponent("examples", isDirectory: true)
    }

    var resolvedControllerRoot: String? {
        // Only ever reveal the canonical, app-owned controller root. Trusting an arbitrary
        // value reported by the running controller (which may be a stray/dev install with the
        // same launch-agent label) is how a second, unexpected folder can surface.
        let canonicalRoot = controllerRootToReveal.path
        guard FileManager.default.fileExists(atPath: canonicalRoot) else { return nil }
        return canonicalRoot
    }

    var resolvedExampleProfilesDirectory: String? {
        for target in [
            profilesDirectory.map { URL(fileURLWithPath: $0).appendingPathComponent("examples").path },
            resolvedControllerRoot.map { URL(fileURLWithPath: $0).appendingPathComponent("model-profiles/examples").path },
        ].compactMap({ $0 }) where FileManager.default.fileExists(atPath: target) {
            return target
        }
        return nil
    }

    nonisolated static func userFacingErrorDescription(
        for error: Error,
        actionName: String? = nil,
        status: ModelProfileStatus? = nil,
        diagnostic: ProfileDiagnostic? = nil,
        isLocal: Bool = false
    ) -> String {
        if let mapped = mapATSError(error) {
            return mapped
        }
        if let mapped = UserFacingControllerError.description(for: error, isLocal: isLocal) {
            return mapped
        }
        guard UserFacingControllerError.isTimeout(error) else { return error.localizedDescription }

        let profileName = status?.displayName ?? diagnostic?.displayName
        let subject = profileName.map { " for \($0)" } ?? ""
        let action = actionName ?? "Request"
        var message = "\(action) timed out\(subject)."

        if let profileError = diagnostic?.errors.first {
            message += " Profile issue: \(profileError)"
        } else {
            message += " The model may still be launching; refresh after it finishes or run Controller Doctor."
        }
        return message
    }

    /// Record a transient refresh/action failure unless a sticky gateway
    /// diagnostic (`.blocked`) is active - refresh failures must not clobber it.
    func recordRefreshFailure(
        _ error: Error,
        actionName: String? = nil,
        profile: String? = nil
    ) {
        if case .blocked = refreshState { return }
        isRecoveringFromTransportFailure = Self.isTransientReachabilityFailure(error)
        refreshState = .failed(
            message: Self.userFacingErrorDescription(
                for: error,
                actionName: actionName,
                status: profile.flatMap(statusForProfile),
                diagnostic: profile.flatMap(diagnosticForProfile),
                isLocal: gateway.isLocal
            )
        )
    }

    /// ATS is app-target-only (rebuild / tunnel remediation). Other transport
    /// copy lives in `UserFacingControllerError` so the widget shares it.
    nonisolated static func mapATSError(_ error: Error) -> String? {
        let chain = UserFacingControllerError.nsErrorChain(error)
        // NSURLErrorAppTransportSecurityRequiresSecureConnection == -1022
        // NSURLErrorSecureConnectionFailed == -1200
        let isATS = chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1022
        } || chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1200
        }
        if isATS {
            return "Blocked plain HTTP to this gateway (App Transport Security). Rebuild the app with ATS exceptions, or switch the gateway to SSH tunnel."
        }
        return nil
    }

    nonisolated static func isTransientReachabilityFailure(_ error: Error) -> Bool {
        UserFacingControllerError.isTransient(error)
    }

    nonisolated static func isTimeout(_ error: Error) -> Bool {
        UserFacingControllerError.isTimeout(error)
    }
}
