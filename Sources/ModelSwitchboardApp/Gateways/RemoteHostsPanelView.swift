import SwiftUI
import ModelSwitchboardCore

/// SparkDash-like live view of each remote gateway's CPU / RAM / GPU / VRAM.
struct RemoteHostsPanelView: View {
    @Bindable var hub: GatewayHub
    @Bindable var metricsMonitor: RemoteHostMetricsMonitor
    let theme: DashboardTheme
    let accent: Color
    @State var didCopyInstallCommand = false
    @State var renamingGatewayID: String?
    @State var renameDraft = ""
    @State var renameError: String?
    @AppStorage(DisplayPrivacy.defaultsKey) var hideHostInfo = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                remoteHostCards
            }
            .padding(12)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await attachAndPollMetrics() }
        .onDisappear {
            // Keep polling while the main panel is open; only stop when the
            // whole menu tears down (MenuBarContentView.onDisappear).
        }
    }
}
