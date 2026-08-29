import AppKit
import SwiftUI
import ModelSwitchboardCore

/// SparkDash-like live view of each remote gateway's CPU / RAM / GPU / VRAM.
struct RemoteHostsPanelView: View {
    @Bindable var hub: GatewayHub
    @Bindable var metricsMonitor: RemoteHostMetricsMonitor
    let theme: DashboardTheme
    let accent: Color
    @State private var didCopyInstallCommand = false
    @State private var renamingGatewayID: String?
    @State private var renameDraft = ""
    @State private var renameError: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if hub.enabledRemoteRuntimes.isEmpty {
                    emptyState
                } else {
                    ForEach(hub.enabledRemoteRuntimes) { runtime in
                        gatewayCard(runtime: runtime, entry: metricsMonitor.entry(forGatewayID: runtime.id))
                    }
                }
            }
            .padding(12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            metricsMonitor.attach(hub: hub)
            metricsMonitor.start()
            await metricsMonitor.pollOnce()
        }
        .onDisappear {
            // Keep polling while the main panel is open; only stop when the
            // whole menu tears down (MenuBarContentView.onDisappear).
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No remote gateways")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.label)
            Text("Add a remote host in Settings to see GPU, VRAM, CPU, and RAM here.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func gatewayCard(runtime: GatewayRuntime, entry: RemoteHostMetricsMonitor.Entry) -> some View {
        let metrics = entry.metrics
        let primaryGPU = metrics?.gpus.first
        let agentStale = RemoteAgentVersion.isRemoteStale(
            metrics: metrics,
            unsupported: entry.unsupported
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(statusColor(runtime: runtime, entry: entry))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    if renamingGatewayID == runtime.id {
                        HStack(spacing: 6) {
                            TextField("Display name", text: $renameDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13, weight: .semibold))
                                .onSubmit { commitRename(id: runtime.id) }
                            Button("Save") { commitRename(id: runtime.id) }
                                .buttonStyle(QuietCraftPressStyle())
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(accent)
                            Button("Cancel") {
                                renamingGatewayID = nil
                                renameDraft = ""
                                renameError = nil
                            }
                            .buttonStyle(QuietCraftPressStyle())
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.sub)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(runtime.name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(theme.label)
                                .lineLimit(1)
                            Button {
                                renamingGatewayID = runtime.id
                                renameDraft = runtime.name
                                renameError = nil
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .frame(width: 26, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(QuietCraftPressStyle())
                            .help("Rename this gateway")
                            .accessibilityLabel("Rename " + runtime.name)
                        }
                    }
                    if let renameError, renamingGatewayID == runtime.id {
                        Text(renameError)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DashboardTheme.stopRed)
                    }
                    Text(subtitle(runtime: runtime, metrics: metrics))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                GatewayForceUpdateControls(
                    runtime: runtime,
                    agentStale: agentStale,
                    remoteVersion: metrics?.agentVersion,
                    theme: theme,
                    accent: accent,
                    capsuleUpdate: true,
                    onUpdate: {
                        Task {
                            await hub.forceUpdateGateway(id: runtime.id)
                            await metricsMonitor.pollOnce()
                        }
                    }
                )
            }

            if case .failed(let message) = runtime.forceUpdatePhase {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.stopRed)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .updating(let step) = runtime.forceUpdatePhase {
                Text(step)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
            } else if agentStale, !entry.unsupported {
                Text(GatewayConnectionBadge.help(
                    for: runtime,
                    agentStale: true,
                    remoteVersion: metrics?.agentVersion
                ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(DashboardTheme.pendingOrange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = entry.error, metrics == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(DashboardTheme.stopRed.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.unsupported {
                        Text(agentUpgradeHint(for: runtime))
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                        copyInstallCommandRow
                    }
                }
            } else {
                HStack(spacing: 6) {
                    metricTile(
                        label: "CPU",
                        value: HostMetricsPresentation.percentLabel(metrics?.cpuPercent),
                        detail: nil
                    )
                    metricTile(
                        label: "RAM",
                        value: HostMetricsPresentation.percentLabel(metrics?.memory?.percent),
                        detail: memoryDetail(metrics?.memory)
                    )
                    metricTile(
                        label: "GPU",
                        value: HostMetricsPresentation.percentLabel(primaryGPU?.utilPercent),
                        detail: primaryGPU?.tempC.map { String(format: "%.0f°C", $0) }
                    )
                    metricTile(
                        label: "VRAM",
                        value: HostMetricsPresentation.percentLabel(
                            HostMetricsPresentation.hostVRAMPercent(metrics)
                        ),
                        detail: HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics)
                    )
                }

                if let gpus = metrics?.gpus, gpus.count > 1 {
                    ForEach(gpus) { gpu in
                        Text(gpuLine(gpu))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(theme.sub)
                            .lineLimit(1)
                    }
                } else if let gpu = primaryGPU, let name = gpu.name, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.sub)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let error = entry.error, entry.unsupported == false {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.faint)
                        .lineLimit(2)
                }
            }

            // Running models on this gateway (with VRAM when known).
            let running = runtime.store.sortedStatuses.filter {
                MenuBarContentView.isDisplayedRunning($0, in: runtime.store)
            }
            if !running.isEmpty {
                theme.line.frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODELS")
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(theme.faint)
                    ForEach(running) { status in
                        HStack(spacing: 6) {
                            Text(status.displayName)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(theme.label)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(HostMetricsPresentation.profileMemoryLabel(
                                status: status,
                                metrics: metrics,
                                isRunning: true
                            ) ?? "— · :" + status.port)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(theme.sub)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
    }

    private func metricTile(label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(theme.sub)
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(accent)
            if let detail {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.faint)
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(.system(size: 9.5))
                    .hidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
        .background(theme.panelBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metricAccessibilityLabel(label: label, value: value, detail: detail))
    }

    private func metricAccessibilityLabel(label: String, value: String, detail: String?) -> String {
        if let detail, !detail.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(label) \(value), \(detail)"
        }
        return "\(label) \(value)"
    }

    private func memoryDetail(_ memory: HostMemoryMetrics?) -> String? {
        guard let used = memory?.usedMB, let total = memory?.totalMB, total > 0 else { return nil }
        return String(format: "%.0f/%.0f GB", used / 1024, total / 1024)
    }

    private func gpuLine(_ gpu: HostGPUMetrics) -> String {
        var parts: [String] = []
        if let index = gpu.index { parts.append("GPU\(index)") }
        if let name = gpu.name { parts.append(name) }
        if let util = gpu.utilPercent { parts.append(String(format: "%.0f%%", util)) }
        if let temp = gpu.tempC { parts.append(String(format: "%.0f°C", temp)) }
        if let used = gpu.vramUsedMB, let total = gpu.vramTotalMB {
            parts.append(String(format: "%.1f/%.1f GB", used / 1024, total / 1024))
        }
        return parts.joined(separator: " · ")
    }

    private func commitRename(id: String) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            renameError = "Give this gateway a name."
            return
        }
        _ = hub.renameGateway(id: id, to: trimmed)
        renamingGatewayID = nil
        renameDraft = ""
        renameError = nil
    }

    private func agentUpgradeHint(for runtime: GatewayRuntime) -> String {
        switch runtime.config.connection {
        case .ssh:
            return "Click Update to push a fresh agent from this Mac (or use Settings → Install Agent / the one-liner below). Until then only process RSS is shown, not GPU VRAM."
        case .direct:
            return "Click Update to push a fresh agent over SSH to this Tailscale host. Login uses your Mac username unless you SSH as a different user. Or paste the one-liner below on the box."
        }
    }

    private var copyInstallCommandRow: some View {
        HStack(spacing: 8) {
            Text(GatewaySettingsSection.installOneLiner)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.faint)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(GatewaySettingsSection.installOneLiner, forType: .string)
                didCopyInstallCommand = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    didCopyInstallCommand = false
                }
            } label: {
                Image(systemName: didCopyInstallCommand ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(didCopyInstallCommand ? DashboardTheme.runningGreen : accent)
                    .frame(width: 28, height: 28)
                    .background(theme.btnBg, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(didCopyInstallCommand ? "Copied" : "Copy install command")
            .accessibilityLabel(didCopyInstallCommand ? "Copied install command" : "Copy install command")
        }
        .padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 6))
        .background(theme.panelBg.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }


    private func subtitle(runtime: GatewayRuntime, metrics: HostMetricsPayload?) -> String {
        if let host = metrics?.host, !host.isEmpty {
            return host
        }
        return runtime.config.endpointSummary
    }

    private func statusColor(runtime: GatewayRuntime, entry: RemoteHostMetricsMonitor.Entry) -> Color {
        if case .failed = runtime.tunnelState { return DashboardTheme.stopRed }
        if entry.error != nil, entry.metrics == nil { return DashboardTheme.pendingOrange }
        if entry.metrics != nil { return DashboardTheme.runningGreen }
        return theme.dotOff
    }
}
