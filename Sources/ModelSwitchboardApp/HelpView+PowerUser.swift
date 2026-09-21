import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    var powerUserBullets: [String] {
        var bullets = [
            "Raycast users can add the repo's `Integrations/Raycast/Script Commands` folder directly in Raycast for keyboard-first actions.",
            "`model-switchboardctl` (from a source `Scripts/install.sh`) exposes `status`, `activate`, `stop-all`, and `open-profiles` without touching the menu bar.",
        ]
        if features.supportsBenchmarks {
            bullets.append("Benchmark controls live in the Plus edition, and results are viewable directly in the in-app Benchmarks panel.")
        }
        return bullets
    }
}
