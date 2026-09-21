import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    @ViewBuilder
    var exampleProfilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Example Profiles")
                .font(.caption.bold())
                .foregroundStyle(theme.faint)

            Text("Use the bundled example manifests as clean starting points for `llama.cpp`, MLX, `rvllm-mlx`, and generic OpenAI-compatible profiles. Copy one, rename it, then fill in your own model path, server binary, and runtime-specific flags.")
                .font(.footnote)
                .foregroundStyle(theme.label)
                .fixedSize(horizontal: false, vertical: true)

            if let exampleProfilesDirectory, !exampleProfilesDirectory.isEmpty {
                Text(exampleProfilesDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.sub)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.hoverBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button("Open Example Profiles", action: openExampleProfilesDirectory)
                .buttonStyle(QuietCraftPressStyle())
                .foregroundStyle(accent)
        }
    }
}
