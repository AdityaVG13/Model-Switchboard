import Foundation
import Darwin

extension SystemMetricsMonitor {
    func sample() {
        cpuUsagePercent = sampleCPUUsage()
        memoryUsagePercent = sampleMemoryUsage()
        gpuUsagePercent = sampleGPUUsage()
        appendHistory(cpuUsagePercent, to: &cpuHistory)
        appendHistory(memoryUsagePercent, to: &memoryHistory)
        appendHistory(gpuUsagePercent, to: &gpuHistory)
    }

    func appendHistory(_ value: Double?, to history: inout [Double]) {
        guard let value else { return }
        history.append(value)
        if history.count > Self.historyLimit {
            history.removeFirst(history.count - Self.historyLimit)
        }
    }
}
