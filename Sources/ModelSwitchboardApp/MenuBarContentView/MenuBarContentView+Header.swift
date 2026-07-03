import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    (
                        Text("\(store.displayedReadyProfiles)")
                            .fontWeight(.bold)
                        + Text("/\(store.summary.totalProfiles)")
                            .fontWeight(.medium)
                            .foregroundStyle(theme.faint)
                    )
                    .font(.system(size: 22).monospacedDigit())
                    Text("models ready")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.sub)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.displayedReadyProfiles) of \(store.summary.totalProfiles) models ready")

                Spacer()

                HStack(spacing: 8) {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button {
                            Task { await store.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh")
                        .help("Refresh status")
                    }
                    Text("v\(Self.appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.faint)
                }
            }

            if features.supportsBenchmarks {
                utilizationGrid
            }

            DashboardSegmentedTabs(
                options: ProfileFilter.allCases,
                label: \.rawValue,
                selection: $profileFilter,
                theme: theme
            )
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14))
    }

    var utilizationGrid: some View {
        HStack(spacing: 6) {
            utilizationCell(label: "CPU", value: systemMetrics.cpuUsagePercent, history: systemMetrics.cpuHistory)
            utilizationCell(label: "RAM", value: systemMetrics.memoryUsagePercent, history: systemMetrics.memoryHistory)
            utilizationCell(label: "GPU", value: systemMetrics.gpuUsagePercent, history: systemMetrics.gpuHistory)
        }
    }

    func utilizationCell(label: String, value: Double?, history: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 9.5))
                    .kerning(0.4)
                    .foregroundStyle(theme.sub)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))%" } ?? "--")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            Sparkline(values: history)
                .stroke(theme.sparkStroke, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(height: 14)
        }
        .padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9))
        .frame(maxWidth: .infinity)
        .background(theme.cellBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(label == "GPU" && value == nil ? "GPU percentage unavailable on this macOS API path." : "")
    }
}
