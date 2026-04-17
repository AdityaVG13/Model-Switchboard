import SwiftUI

struct LeverSwitchIcon: View {
    let hasReadyModels: Bool
    let hasRunningModels: Bool
    var size: CGFloat = 18

    private var systemName: String {
        if hasReadyModels {
            return "memorychip.fill"
        }
        if hasRunningModels {
            return "memorychip"
        }
        return "cpu"
    }

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: size * 0.95, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}
