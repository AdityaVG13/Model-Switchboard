import AppKit
import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    var canReopenLastActive: Bool {
        features.supportsBenchmarks &&
        !lastActiveProfiles.isEmpty &&
        // Only offer reopen when those profiles still exist in this store
        // (avoids a dead "Reopen Last Active" after profiles were removed).
        lastActiveProfiles.contains { name in statuses.contains { $0.profile == name } } &&
        !pendingGlobalActions.contains(.reopenLastActive) &&
        !statuses.contains(where: \.running) &&
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
        guard let profilesDirectory else { return }
        revealInFinder(URL(fileURLWithPath: profilesDirectory))
    }

    func openControllerRoot() {
        guard let target = resolvedControllerRoot else { return }
        revealInFinder(URL(fileURLWithPath: target))
    }

    func openExampleProfilesDirectory() {
        guard let target = resolvedExampleProfilesDirectory else { return }
        revealInFinder(URL(fileURLWithPath: target))
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

    var resolvedControllerRoot: String? {
        // Only ever reveal the canonical, app-owned controller root. Trusting an arbitrary
        // value reported by the running controller (which may be a stray/dev install with the
        // same launch-agent label) is how a second, unexpected folder can surface.
        let canonicalRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ModelSwitchboard/Controller")
            .path
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

    static func userFacingErrorDescription(
        for error: Error,
        actionName: String? = nil,
        status: ModelProfileStatus? = nil,
        diagnostic: ProfileDiagnostic? = nil
    ) -> String {
        if let mapped = mapTransportError(error) {
            return mapped
        }
        guard isTimeout(error) else { return error.localizedDescription }

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
        refreshState = .failed(
            message: Self.userFacingErrorDescription(
                for: error,
                actionName: actionName,
                status: profile.flatMap(statusForProfile),
                diagnostic: profile.flatMap(diagnosticForProfile)
            )
        )
    }

    /// Map raw URLSession / ATS / socket failures to short dashboard copy.
    /// Code-based only: NSError domain+code (URLError, POSIX, ATS -1022/-1200)
    /// walked through the underlying-error chain. Never sniffs
    /// localizedDescription text.
    static func mapTransportError(_ error: Error) -> String? {
        let nsError = error as NSError
        var chain: [NSError] = [nsError]
        var current: NSError? = nsError
        while let next = current?.userInfo[NSUnderlyingErrorKey] as? NSError {
            chain.append(next)
            current = next
        }

        // NSURLErrorAppTransportSecurityRequiresSecureConnection == -1022
        // NSURLErrorSecureConnectionFailed == -1200 (previously matched via the
        // "secure connection" text; kept code-based so those errors keep the
        // same ATS copy instead of regressing to the generic description).
        let isATS = chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1022
        } || chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1200
        }
        if isATS {
            return "Blocked plain HTTP to this gateway (App Transport Security). Rebuild the app with ATS exceptions, or switch the gateway to SSH tunnel."
        }

        for entry in chain {
            if entry.domain == NSURLErrorDomain {
                switch URLError.Code(rawValue: entry.code) {
                case .notConnectedToInternet:
                    return "No network route to the gateway."
                case .cannotFindHost, .dnsLookupFailed:
                    return "Gateway host not found. Check MagicDNS / hostname."
                case .cannotConnectToHost:
                    return "Gateway refused the connection. Is the agent running?"
                case .networkConnectionLost:
                    return "Connection to the gateway was lost."
                case .userAuthenticationRequired, .userCancelledAuthentication:
                    return "Gateway rejected the request (auth). Check the bearer token in Settings."
                default:
                    break
                }
            } else if entry.domain == NSPOSIXErrorDomain {
                // POSIX socket codes surfacing from lower layers (tunnel, runner).
                switch entry.code {
                case Int(ECONNREFUSED):
                    return "Gateway refused the connection. Is the agent running?"
                case Int(ENETUNREACH), Int(EHOSTUNREACH):
                    return "No network route to the gateway."
                case Int(ECONNRESET), Int(ENOTCONN):
                    return "Connection to the gateway was lost."
                default:
                    break
                }
            }
        }
        return nil
    }

    static func isTimeout(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
            || nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ETIMEDOUT)
    }
}
