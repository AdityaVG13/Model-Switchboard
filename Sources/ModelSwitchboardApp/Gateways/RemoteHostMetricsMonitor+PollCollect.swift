import Foundation
import ModelSwitchboardCore

extension RemoteHostMetricsMonitor {
    func collectHostMetricsResults(
        _ targets: [RemoteHostMetricsPollTarget]
    ) async -> [(String, Entry)] {
        await withTaskGroup(
            of: (String, Entry).self,
            returning: [(String, Entry)].self
        ) { group in
            for target in targets {
                group.addTask {
                    await resolveHostMetricsEntry(target: target)
                }
            }
            var collected: [(String, Entry)] = []
            collected.reserveCapacity(targets.count)
            for await item in group {
                collected.append(item)
            }
            return collected
        }
    }
}
