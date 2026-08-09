import AppKit
import SwiftUI
import ModelSwitchboardCore


enum ProfileHeroStatusCopy {
    /// Board/hero status line for local or remote profiles.
    static func label(
        ready: Bool,
        running: Bool,
        pending: String?,
        gatewayName: String?
    ) -> String {
        if let gatewayName {
            let host = gatewayName.uppercased()
            if let pending {
                return "\(pending.uppercased()) ON \(host)"
            }
            if ready { return "ACTIVE ON \(host)" }
            if running { return "WARMING ON \(host)" }
            return "STARTING ON \(host)"
        }
        if let pending { return pending }
        if ready { return "ACTIVE" }
        if running { return "WARMING" }
        return "STARTING"
    }
}

/// Shared list-row chrome for local and remote profiles.
struct ProfileListRowView: View {
    let profile: ModelProfileStatus
    let store: SwitchboardStore
    var hostMetrics: HostMetricsPayload? = nil
    /// Mac-reachable endpoint (SSH forward / direct rewrite). Nil hides the
    /// extra endpoint line and disables Copy when `showReachability` is true.
    var reachableEndpointURL: String? = nil
    var showReachability: Bool = false
    var endpointUnavailableHint: String? = nil
    /// When set, Benchmark menu item is labeled for that gateway.
    var gatewayDisplayName: String? = nil
    var onOpenBenchmarks: (() -> Void)? = nil
    let theme: DashboardTheme
    let accent: Color

    private var isDisplayedRunning: Bool {
        MenuBarContentView.isDisplayedRunning(profile, in: store)
    }

    private var pending: String? {
        store.pendingLabel(for: profile.profile)
    }

    private var isBusy: Bool { pending != nil }

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(theme.label)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
                if let endpointLine {
                    Text(endpointLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rowAccessibilityLabel)

            HStack(spacing: 4) {
                primaryButton
                rowMenu
            }
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
        .contentShape(Rectangle())
        .background(RowHoverHighlight(color: theme.hoverBg))
    }

    private var dotColor: Color {
        switch store.profileBadgeState(for: profile, relativeTo: .now) {
        case .pending:
            return DashboardTheme.pendingOrange
        case .running:
            return DashboardTheme.runningGreen
        case .stale, .notRunning:
            return theme.dotOff
        }
    }

    private var subtitle: String {
        var parts = [profile.runtimeLabel ?? profile.runtime, ":\(profile.port)"]
        if let pending {
            parts.append(pending.lowercased() + "…")
        } else if let memory = HostMetricsPresentation.profileMemoryLabel(
            status: profile,
            metrics: hostMetrics,
            isRunning: isDisplayedRunning
        ) {
            parts.append(memory)
        }
        let benchRows = store.benchmark?.latest?.rows.filter { $0.profile == profile.profile } ?? []
        if let tok = benchRows.compactMap(\.decodeTokensPerSec).max() {
            parts.append(String(format: "%.1f t/s", tok))
        }
        if let best = benchRows.max(by: { ($0.decodeTokensPerSec ?? -1) < ($1.decodeTokensPerSec ?? -1) }),
           let ttft = best.ttftMS {
            parts.append(String(format: "%.0f ms", ttft))
        }
        if showReachability, isDisplayedRunning, reachableEndpointURL == nil {
            parts.append(endpointUnavailableHint ?? "not reachable")
        }
        return parts.joined(separator: " · ")
    }

    private var rowAccessibilityLabel: String {
        if let endpointLine {
            return "\(profile.displayName), \(subtitle), \(endpointLine)"
        }
        return "\(profile.displayName), \(subtitle)"
    }

    /// `<served model id> · <URL usable from this Mac>` for live remote rows.
    private var endpointLine: String? {
        guard showReachability, isDisplayedRunning, profile.ready else { return nil }
        let servedModel = profile.serverIDs.first ?? profile.serverModelID
        guard let url = reachableEndpointURL else {
            let why = endpointUnavailableHint ?? "not reachable from this Mac"
            return "\(servedModel) · \(profile.host):\(profile.port) (\(why))"
        }
        return "\(servedModel) · \(url)"
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isBusy {
            iconContainer {
                ProgressView()
                    .controlSize(.mini)
            }
            .accessibilityLabel(
                pending.map { "\($0) \(profile.displayName)" } ?? "Working on \(profile.displayName)"
            )
        } else if isDisplayedRunning {
            actionIcon("stop.fill", color: DashboardTheme.stopRed, label: "Stop \(profile.displayName)") {
                Task { await store.stop(profile.profile) }
            }
        } else {
            actionIcon(
                "play.fill",
                color: accent,
                label: "Activate \(profile.displayName)",
                hint: "Stops other models on this gateway, then starts this one"
            ) {
                Task { await store.activate(profile.profile) }
            }
        }
    }

    private var rowMenu: some View {
        let canBenchmark = store.features.supportsBenchmarks
            && profile.ready
            && store.canStartBenchmarkNow
            && !store.isBenchmarkInFlight(for: profile.profile)
        let benchmarkLabel: String = {
            if let gatewayDisplayName {
                return "Benchmark on \(gatewayDisplayName)"
            }
            return "Benchmark"
        }()
        return Menu {
            Button("Start without stopping others") {
                Task { await store.start(profile.profile) }
            }
            .disabled(isBusy || profile.running)
            Button("Restart") {
                Task { await store.restart(profile.profile) }
            }
            .disabled(isBusy)
            if store.features.supportsBenchmarks {
                Divider()
                if canBenchmark {
                    Button(benchmarkLabel) {
                        onOpenBenchmarks?()
                        Task { await store.quickBenchmark([profile.profile]) }
                    }
                } else if !profile.ready {
                    Button("Benchmark disabled · model not ready on :\(profile.port)") {}
                        .disabled(true)
                } else if store.benchmark?.running == true {
                    Button("Benchmark running\(gatewayDisplayName.map { " on \($0)" } ?? "")…") {}
                        .disabled(true)
                } else if !store.canStartBenchmarkNow {
                    Button("Benchmark cooling down") {}
                        .disabled(true)
                } else {
                    Button("Benchmark unavailable") {}
                        .disabled(true)
                }
            }
            Divider()
            if showReachability {
                if let reachableEndpointURL {
                    Button("Copy Endpoint URL") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(reachableEndpointURL, forType: .string)
                    }
                } else {
                    Button("Endpoint not reachable from this Mac") {}
                        .disabled(true)
                }
            } else {
                Button("Copy Endpoint URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(profile.baseURL, forType: .string)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.sub)
                .frame(width: 26, height: 26)
                .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More actions for \(profile.displayName)")
    }

    private func actionIcon(
        _ systemName: String,
        color: Color,
        label: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconContainer {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(QuietCraftPressStyle())
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
    }

    private func iconContainer(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 26, height: 26)
            .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Shared hero card for the active local or remote profile.
struct ActiveProfileHeroView: View {
    enum Context: Equatable {
        case local
        case remote(gatewayName: String)
    }

    let profile: ModelProfileStatus
    let store: SwitchboardStore
    var context: Context = .local
    var hostMetrics: HostMetricsPayload? = nil
    var decodeTokensPerSecond: Double? = nil
    var ttftMilliseconds: Double? = nil
    /// Mac-reachable URL for remote heroes (forwarded / rewritten).
    var reachableEndpointURL: String? = nil
    var onOpenBenchmarks: (() -> Void)? = nil
    let theme: DashboardTheme
    let accent: Color

    private var isBusy: Bool {
        store.isBusy(profile: profile.profile)
    }

    private var statusLabel: String {
        switch context {
        case .local:
            return ProfileHeroStatusCopy.label(
                ready: profile.ready,
                running: profile.running,
                pending: store.pendingLabel(for: profile.profile),
                gatewayName: nil
            )
        case .remote(let name):
            return ProfileHeroStatusCopy.label(
                ready: profile.ready,
                running: profile.running,
                pending: store.pendingLabel(for: profile.profile),
                gatewayName: name
            )
        }
    }

    private var subtitle: String {
        switch context {
        case .local:
            return "\(profile.runtimeLabel ?? profile.runtime) · \(profile.baseURL)"
        case .remote:
            let endpoint = reachableEndpointURL ?? "\(profile.host):\(profile.port)"
            return "\(profile.runtimeLabel ?? profile.runtime) · \(endpoint)"
        }
    }

    private var canBenchmark: Bool {
        store.features.supportsBenchmarks
            && profile.ready
            && store.canStartBenchmarkNow
            && !store.isBenchmarkInFlight(for: profile.profile)
    }

    private var benchmarkHelp: String {
        switch context {
        case .local:
            return "Run a quick benchmark on This Mac."
        case .remote(let name):
            if !profile.ready {
                return "Benchmark disabled: model on :\(profile.port) is not ready yet."
            }
            if !store.canStartBenchmarkNow {
                return "Benchmark cooling down or already running on \(name)."
            }
            return "Run a quick benchmark on \(name) via the remote agent (uses the model on that host)."
        }
    }

    private var showsURLSelection: Bool {
        switch context {
        case .local:
            return true
        case .remote:
            return reachableEndpointURL != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isBusy ? DashboardTheme.pendingOrange : DashboardTheme.runningGreen)
                            .frame(width: 6, height: 6)
                        Text(statusLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(accent)
                    }
                    Text(profile.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(theme.label)
                    Text(subtitle)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .modifier(LocalURLSelection(enabled: showsURLSelection))
                }
                Spacer(minLength: 0)
                trailingMetric
            }

            HStack(spacing: 6) {
                HoldToConfirmTextButton(
                    title: "Stop",
                    color: DashboardTheme.stopRed,
                    isBusy: isBusy,
                    disabled: isBusy,
                    helpDetail: isBusy ? "Busy" : "Stop \(profile.displayName)",
                    chrome: .filled(background: theme.btnStrongBg, foreground: theme.btnStrongFg)
                ) {
                    Task { await store.stop(profile.profile) }
                }
                actionButton("Restart", disabled: isBusy) {
                    Task { await store.restart(profile.profile) }
                }
                if store.features.supportsBenchmarks {
                    actionButton("Benchmark", disabled: isBusy || !canBenchmark) {
                        onOpenBenchmarks?()
                        Task { await store.quickBenchmark([profile.profile]) }
                    }
                    .help(benchmarkHelp)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.13), accent.opacity(0.05)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 0, trailing: 10))
    }

    @ViewBuilder
    private var trailingMetric: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch context {
            case .local:
                if let tok = decodeTokensPerSecond {
                    Text(String(format: "%.1f", tok))
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(accent)
                    Text("t/s")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.sub)
                }
                if let ttft = ttftMilliseconds {
                    Text(String(format: "%.0f ms", ttft))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(theme.sub)
                        .accessibilityLabel("TTFT \(Int(ttft.rounded())) milliseconds")
                }
            case .remote:
                if let pct = HostMetricsPresentation.hostVRAMPercent(hostMetrics) {
                    Text("\(Int(pct.rounded()))%")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(accent)
                    Text("VRAM")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.sub)
                    if let detail = HostMetricsPresentation.hostVRAMUsedTotalLabel(hostMetrics) {
                        Text(detail)
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(theme.sub)
                    }
                }
                if let bench = compactRemoteBenchLabel {
                    Text(bench)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(theme.sub)
                        .accessibilityLabel("Benchmark \(bench)")
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var compactRemoteBenchLabel: String? {
        var parts: [String] = []
        if let tok = decodeTokensPerSecond {
            parts.append(String(format: "%.1f t/s", tok))
        }
        if let ttft = ttftMilliseconds {
            parts.append(String(format: "%.0f ms", ttft))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }


    private func actionButton(
        _ title: String,
        strong: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: strong ? .semibold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    strong ? theme.btnStrongBg : theme.btnBg,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .foregroundStyle(strong ? theme.btnStrongFg : theme.btnFg)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietCraftPressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

private struct LocalURLSelection: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}
