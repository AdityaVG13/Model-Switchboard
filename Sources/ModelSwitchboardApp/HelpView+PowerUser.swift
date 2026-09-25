import SwiftUI
import ModelSwitchboardCore

extension HelpView {
    var powerUserBullets: [String] {
        [
            "Raycast users can add the repo's `Integrations/Raycast/Script Commands` folder directly in Raycast for keyboard-first actions.",
            "`model-switchboardctl` (from a source `Scripts/install.sh`) exposes `status`, `activate`, `stop-all`, and `open-profiles` without touching the menu bar.",
            "Benchmark controls live in the footer, and results are viewable directly in the in-app Benchmarks panel.",
        ]
    }
}
