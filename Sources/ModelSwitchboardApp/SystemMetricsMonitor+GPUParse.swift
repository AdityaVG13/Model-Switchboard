import Foundation
import IOKit
import Darwin

extension SystemMetricsMonitor {
    func parseGPUUsage(from properties: MetricsDictionary) -> Double? {
        let containers: [MetricsDictionary] = [
            properties,
            properties["PerformanceStatistics"] as? MetricsDictionary,
            properties["Statistics"] as? MetricsDictionary
        ]
            .compactMap { $0 }

        let usageKeys = [
            "Device Utilization %",
            "GPU Core Utilization",
            "GPU Busy",
            "GPU Usage",
            "PercentBusy",
            "Utilization"
        ]

        for container in containers {
            for key in usageKeys {
                guard let rawValue = container[key] else { continue }
                if let usage = normalizePercentage(rawValue) {
                    return usage
                }
            }
        }

        return nil
    }
}
