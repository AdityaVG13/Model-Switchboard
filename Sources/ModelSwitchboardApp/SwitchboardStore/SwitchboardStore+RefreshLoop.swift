import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    func runAutoRefreshLoop() async {
        await refresh()
        while !Task.isCancelled {
            let interval = autoRefreshPolicy.interval
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                if isBenignCancellation(error) { break }
                Self.logger.error("Auto refresh sleep failed: \(String(describing: error), privacy: .public)")
                break
            }
            if Task.isCancelled { break }
            await refresh()
        }
    }
}
