import SwiftUI
import ModelSwitchboardCore

extension GatewaySettingsSection {
    @ViewBuilder
    var pairingPasteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            field(
                "Paste pairing code",
                text: $linkCode,
                prompt: "modelswitchboard-gateway://…",
                monospaced: true
            )
            Text("On the host, install the agent then run `model-switchboard-agent link`. Paste what it prints. Works for Spark, a lab box, or any other machine.")
                .font(.system(size: 10))
                .foregroundStyle(theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: linkCode) { _, newValue in
            applyPairingCode(newValue)
        }
    }

    func applyPairingCode(_ raw: String) {
        guard var parsed = GatewayLinkCode.parse(raw) else { return }
        if let existing = draft {
            parsed.id = existing.id
        } else {
            draftIsNew = true
        }
        draft = parsed
        validationMessage = nil
    }
}
