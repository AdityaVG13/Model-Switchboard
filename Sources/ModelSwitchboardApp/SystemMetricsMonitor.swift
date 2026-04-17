import Foundation
import IOKit
import Darwin

@MainActor
final class SystemMetricsMonitor: ObservableObject {
    @Published var cpuUsagePercent: Double?
    @Published var gpuUsagePercent: Double?

    private struct CPUSample {
        let totalTicks: UInt64
        let idleTicks: UInt64
    }

    private typealias MetricsDictionary = [String: AnyObject]

    private var timer: Timer?
    private var previousCPUSample: CPUSample?

    func start(interval: TimeInterval = 5) {
        guard timer == nil else { return }
        sample()

        let nextTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        previousCPUSample = nil
    }

    private func sample() {
        cpuUsagePercent = sampleCPUUsage()
        gpuUsagePercent = sampleGPUUsage()
    }

    private func sampleCPUUsage() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let user = UInt64(load.cpu_ticks.0)
        let system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2)
        let nice = UInt64(load.cpu_ticks.3)
        let total = user + system + idle + nice
        let current = CPUSample(totalTicks: total, idleTicks: idle)
        defer { previousCPUSample = current }

        guard let previousCPUSample else { return nil }
        let totalDelta = current.totalTicks &- previousCPUSample.totalTicks
        let idleDelta = current.idleTicks &- previousCPUSample.idleTicks
        guard totalDelta > 0 else { return nil }

        let busyFraction = max(0, min(1, 1 - (Double(idleDelta) / Double(totalDelta))))
        return busyFraction * 100
    }

    private func sampleGPUUsage() -> Double? {
        for className in ["AGXAccelerator", "IOAccelerator", "IOGPU"] {
            if let value = sampleGPUUsage(matchingClass: className) {
                return value
            }
        }
        return nil
    }

    private func sampleGPUUsage(matchingClass className: String) -> Double? {
        guard let matching = IOServiceMatching(className) else { return nil }
        var iterator: io_iterator_t = 0
        let status = IOServiceGetMatchingServices(ioMainPort, matching, &iterator)
        guard status == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard let properties = copyProperties(for: service) else { continue }
            if let usage = parseGPUUsage(from: properties) {
                return usage
            }
        }

        return nil
    }

    private func copyProperties(for service: io_object_t) -> MetricsDictionary? {
        var rawProperties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &rawProperties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let rawProperties else { return nil }
        return rawProperties.takeRetainedValue() as? MetricsDictionary
    }

    private func parseGPUUsage(from properties: MetricsDictionary) -> Double? {
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

    private func normalizePercentage(_ value: AnyObject) -> Double? {
        if let number = value as? NSNumber {
            return normalizePercentage(number.doubleValue)
        }
        if let text = value as? String, let parsed = Double(text) {
            return normalizePercentage(parsed)
        }
        return nil
    }

    private func normalizePercentage(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        if value >= 0 && value <= 1 {
            return value * 100
        }
        if value >= 0 && value <= 100 {
            return value
        }
        if value > 100 && value <= 10_000 {
            return min(max(value / 100, 0), 100)
        }
        return nil
    }
}

private let ioMainPort: mach_port_t = kIOMainPortDefault
