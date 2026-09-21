import Foundation
import Darwin

extension SystemMetricsMonitor {
    func sampleCPUUsage() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let current = cpuSample(from: load)
        defer { previousCPUSample = current }
        return cpuUsagePercent(previous: previousCPUSample, current: current)
    }

    func cpuSample(from load: host_cpu_load_info) -> CPUSample {
        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        return CPUSample(totalTicks: user + system + idle + nice, idleTicks: idle)
    }

    func cpuUsagePercent(previous: CPUSample?, current: CPUSample) -> Double? {
        guard let previous else { return nil }
        let totalDelta = current.totalTicks &- previous.totalTicks
        let idleDelta = current.idleTicks &- previous.idleTicks
        guard totalDelta > 0 else { return nil }
        let busyFraction = max(0, min(1, 1 - (Double(idleDelta) / Double(totalDelta))))
        return busyFraction * 100
    }
}
