import SwiftUI
import ModelSwitchboardCore

extension MenuBarContentView {
    func decodeTokensPerSecond(for profile: String, in store: SwitchboardStore? = nil) -> Double? {
        let source = store ?? self.store
        return source.benchmark?.latest?.rows
            .filter { $0.profile == profile }
            .compactMap(\.decodeTokensPerSec)
            .max()
    }

    func ttftMilliseconds(for profile: String, in store: SwitchboardStore? = nil) -> Double? {
        let source = store ?? self.store
        let rows = source.benchmark?.latest?.rows.filter { $0.profile == profile } ?? []
        // Prefer the row that produced the best decode rate when both exist.
        if let best = rows.max(by: { ($0.decodeTokensPerSec ?? -1) < ($1.decodeTokensPerSec ?? -1) }) {
            return best.ttftMS
        }
        return rows.compactMap(\.ttftMS).min()
    }

    func runtimeName(_ status: ModelProfileStatus) -> String {
        status.runtimeLabel ?? status.runtime
    }
}
