import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    (
                        Text("\(hub.displayedReadyProfiles)")
                            .fontWeight(.bold)
                            .foregroundStyle(theme.label)
                        + Text("/\(hub.totalProfiles)")
                            .fontWeight(.medium)
                            .foregroundStyle(theme.faint)
                    )
                    .font(.system(size: 22).monospacedDigit())
                    Text("models ready")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.sub)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(hub.displayedReadyProfiles) of \(hub.totalProfiles) models ready")

                Spacer()

                HStack(spacing: 8) {
                    // Keep a fixed-size control: swapping ProgressView for the
                    // button reflows the header and flashes the transparent
                    // MenuBarExtra window (black flicker on spam-refresh).
                    let isRefreshing = hub.allStores.contains(where: \.isRefreshing)
                    Button {
                        hub.refreshAll()
                    } label: {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.faint)
                                .opacity(isRefreshing ? 0 : 1)
                            if isRefreshing {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        .frame(width: DashboardChromeMetrics.footerIconHitSize, height: DashboardChromeMetrics.footerIconHitSize)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(QuietCraftPressStyle())
                    .disabled(isRefreshing)
                    .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
                    .help(isRefreshing ? "Refresh in progress" : "Refresh all gateways")
                    .transaction { $0.animation = nil }
                    // Version lives in Settings — keep the ready count as the hero.
                }
            }

            if features.supportsBenchmarks {
                // Always keep This Mac utilization visible; remote host metrics
                // live in gateway section chips / Remote Hosts, not here.
                utilizationGrid
            }

            DashboardSegmentedTabs(
                options: ProfileFilter.allCases,
                label: \.rawValue,
                selection: $profileFilter,
                theme: theme
            )
        }
        .padding(EdgeInsets(top: 14, leading: DashboardChromeMetrics.continuousCornerSafeInset + 2, bottom: 10, trailing: DashboardChromeMetrics.continuousCornerSafeInset + 2))
    }

    var utilizationGrid: some View {
        HStack(spacing: 6) {
            utilizationCell(label: "CPU", value: systemMetrics.cpuUsagePercent, history: systemMetrics.cpuHistory)
            utilizationCell(label: "RAM", value: systemMetrics.memoryUsagePercent, history: systemMetrics.memoryHistory)
            utilizationCell(label: "GPU", value: systemMetrics.gpuUsagePercent, history: systemMetrics.gpuHistory)
        }
    }

    func utilizationCell(
        label: String,
        value: Double?,
        history: [Double],
        helpText: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9.5))
                    .kerning(0.4)
                    .foregroundStyle(theme.sub)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.label)
            }
            if history.isEmpty {
                Color.clear.frame(height: 14)
            } else {
                Sparkline(values: history)
                    .stroke(theme.sparkStroke, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(height: 14)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9))
        .frame(maxWidth: .infinity)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.panelBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(utilizationAccessibilityLabel(label: label, value: value))
        .modifier(OptionalHelp(text: utilizationHelp(label: label, value: value, helpText: helpText)))
    }

    private func utilizationAccessibilityLabel(label: String, value: Double?) -> String {
        if let value {
            return "\(label) \(Int(value.rounded())) percent"
        }
        return "\(label) unavailable"
    }

    private func utilizationHelp(label: String, value: Double?, helpText: String?) -> String? {
        if let helpText, !helpText.isEmpty { return helpText }
        if label == "GPU", value == nil {
            return "GPU percentage unavailable on this macOS API path."
        }
        return nil
    }
}

private struct OptionalHelp: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}
