import AppKit
import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    // MARK: - Selection helpers

    /// The model featured in the hero card: the first running profile in display order.
    var heroProfile: ModelProfileStatus? {
        store.sortedStatuses.first { $0.running }
    }

    var standbyProfiles: [ModelProfileStatus] {
        let hero = heroProfile?.profile
        return store.sortedStatuses.filter { status in
            status.profile != hero && matchesFilter(status)
        }
    }

    func matchesFilter(_ status: ModelProfileStatus) -> Bool {
        switch profileFilter {
        case .all:
            true
        case .running:
            status.running || store.isBusy(profile: status.profile)
        case .mlx:
            Self.runtimeKind(status) == .mlx
        case .llamaCpp:
            Self.runtimeKind(status) == .llamaCpp
        }
    }

    static func runtimeKind(_ status: ModelProfileStatus) -> ProfileFilter? {
        let haystack = ([status.runtime, status.runtimeLabel ?? ""] + (status.runtimeTags ?? []))
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("llama") { return .llamaCpp }
        if haystack.contains("mlx") { return .mlx }
        return nil
    }

    func decodeTokensPerSecond(for profile: String) -> Double? {
        store.benchmark?.latest?.rows
            .filter { $0.profile == profile }
            .compactMap(\.decodeTokensPerSec)
            .max()
    }

    func runtimeName(_ status: ModelProfileStatus) -> String {
        status.runtimeLabel ?? status.runtime
    }

    func rowSubtitle(_ status: ModelProfileStatus) -> String {
        var parts = [runtimeName(status), ":\(status.port)"]
        if let pending = store.pendingLabel(for: status.profile) {
            parts.append(pending.lowercased() + "…")
        } else if let tok = decodeTokensPerSecond(for: status.profile) {
            parts.append(String(format: "%.1f t/s", tok))
        } else if let rssMB = status.rssMB, status.running {
            parts.append(String(format: "%.1f GB", rssMB / 1024))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hero section

    @ViewBuilder
    var heroSection: some View {
        if let hero = heroProfile {
            heroCard(hero)
        } else if store.canReopenLastActive {
            reopenCard
        }
    }

    func heroCard(_ profile: ModelProfileStatus) -> some View {
        let pending = store.pendingLabel(for: profile.profile)
        let label = pending ?? (profile.ready ? "ACTIVE" : "STARTING")
        let isBusy = store.isBusy(profile: profile.profile)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(DashboardTheme.runningGreen)
                            .frame(width: 6, height: 6)
                            .shadow(color: DashboardTheme.runningGreen.opacity(0.6), radius: 3)
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(accent)
                    }
                    Text(profile.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(runtimeName(profile)) · \(profile.baseURL)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if let tok = decodeTokensPerSecond(for: profile.profile) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.1f", tok))
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(accent)
                        Text("tok/s")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.sub)
                    }
                }
            }

            HStack(spacing: 6) {
                heroButton("■ Stop", strong: true, disabled: isBusy) {
                    Task { await store.stop(profile.profile) }
                }
                heroButton("↻ Restart", disabled: isBusy) {
                    Task { await store.restart(profile.profile) }
                }
                if features.supportsBenchmarks {
                    heroButton("Benchmark", disabled: isBusy || store.isBenchmarkInFlight(for: profile.profile)) {
                        setInspectorPanel(.benchmarks)
                        Task { await store.quickBenchmark([profile.profile]) }
                    }
                }
            }
        }
        .padding(12)
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

    var reopenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTHING RUNNING")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(theme.faint)
            heroButton(
                "↻ Reopen Last Active",
                disabled: store.pendingGlobalActions.contains("reopen-last") || store.pendingGlobalActions.contains("stop-all")
            ) {
                Task { await store.reopenLastActive() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 0, trailing: 10))
    }

    func heroButton(
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
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Model list

    var modelListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardSectionLabel(
                text: heroProfile != nil ? "STANDBY · \(standbyProfiles.count)" : "MODELS · \(standbyProfiles.count)",
                theme: theme
            )
            .padding(EdgeInsets(top: 6, leading: 4, bottom: 4, trailing: 4))

            if standbyProfiles.isEmpty {
                Text(store.sortedStatuses.isEmpty
                    ? "No model profiles reported yet. Check the controller connection in Settings."
                    : "No models match this filter.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.sub)
                    .padding(EdgeInsets(top: 2, leading: 4, bottom: 8, trailing: 4))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(standbyProfiles) { profile in
                    profileRow(profile)
                }
            }
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 6, trailing: 10))
    }

    func profileRow(_ profile: ModelProfileStatus) -> some View {
        let pending = store.pendingLabel(for: profile.profile)
        let isBusy = pending != nil

        return HStack(spacing: 9) {
            Circle()
                .fill(rowDotColor(profile, pending: pending))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(rowSubtitle(profile))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                rowPrimaryButton(profile, pending: pending, isBusy: isBusy)
                rowMenu(profile, isBusy: isBusy)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 6, bottom: 7, trailing: 6))
        .contentShape(Rectangle())
        .background(RowHoverHighlight(color: theme.hoverBg))
    }

    func rowDotColor(_ profile: ModelProfileStatus, pending: String?) -> Color {
        if pending != nil { return DashboardTheme.pendingOrange }
        if profile.running { return DashboardTheme.runningGreen }
        return theme.dotOff
    }

    @ViewBuilder
    func rowPrimaryButton(_ profile: ModelProfileStatus, pending: String?, isBusy: Bool) -> some View {
        if isBusy {
            rowIcon {
                ProgressView()
                    .controlSize(.mini)
            }
        } else if profile.running {
            rowActionIcon("stop.fill", color: DashboardTheme.stopRed, label: "Stop \(profile.displayName)") {
                Task { await store.stop(profile.profile) }
            }
        } else {
            rowActionIcon("play.fill", color: accent, label: "Activate \(profile.displayName)") {
                Task { await store.activate(profile.profile) }
            }
        }
    }

    func rowMenu(_ profile: ModelProfileStatus, isBusy: Bool) -> some View {
        Menu {
            Button("Start (keep others running)") {
                Task { await store.start(profile.profile) }
            }
            .disabled(isBusy || profile.running)
            Button("Restart") {
                Task { await store.restart(profile.profile) }
            }
            .disabled(isBusy)
            if features.supportsBenchmarks {
                Button("Benchmark") {
                    setInspectorPanel(.benchmarks)
                    Task { await store.quickBenchmark([profile.profile]) }
                }
                .disabled(isBusy || store.isBenchmarkInFlight(for: profile.profile))
            }
            Divider()
            Button("Copy Endpoint URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(profile.baseURL, forType: .string)
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

    func rowActionIcon(_ systemName: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowIcon {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    func rowIcon(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(width: 26, height: 26)
            .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// Hover highlight for list rows (SwiftUI has no `style-hover`; track it manually).
struct RowHoverHighlight: View {
    let color: Color
    @State private var isHovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isHovering ? color : .clear)
            .onHover { isHovering = $0 }
    }
}
