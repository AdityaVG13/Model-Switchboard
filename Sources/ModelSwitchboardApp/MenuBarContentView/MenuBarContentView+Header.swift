import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            LeverSwitchIcon(
                hasReadyModels: store.displayedReadyProfiles > 0,
                hasRunningModels: store.displayedRunningProfiles > 0,
                size: 34
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(features.appDisplayName)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                HStack(spacing: 7) {
                    headerMetaItem(
                        icon: "bolt.fill",
                        text: "\(store.displayedReadyProfiles)/\(store.summary.totalProfiles) ready"
                    )
                    footerSeparator()
                    headerMetaItem(icon: "switch.2", text: "local control")
                    footerSeparator()
                    Text("v\(Self.appVersion)")
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if features.supportsBenchmarks {
                    HStack(spacing: 6) {
                        utilizationBadge(label: "CPU", value: systemMetrics.cpuUsagePercent)
                        utilizationBadge(label: "RAM", value: systemMetrics.memoryUsagePercent)
                        utilizationBadge(label: "GPU", value: systemMetrics.gpuUsagePercent)
                    }
                }

                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    func headerMetaItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .imageScale(.small)
            Text(text)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    func utilizationBadge(label: String, value: Double?) -> some View {
        let text: String
        if let value {
            text = "\(label) \(Int(value.rounded()))%"
        } else {
            text = "\(label) --"
        }

        return Text(text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.42), in: Capsule())
            .foregroundStyle(.secondary)
            .help(label == "GPU" && value == nil ? "GPU percentage unavailable on this macOS API path." : "")
    }
}
