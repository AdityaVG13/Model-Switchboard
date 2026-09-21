import Foundation
import IOKit
import Darwin

extension SystemMetricsMonitor {
    func sampleGPUUsage() -> Double? {
        for className in ["AGXAccelerator", "IOAccelerator", "IOGPU"] {
            if let value = sampleGPUUsage(matchingClass: className) {
                return value
            }
        }
        return nil
    }

    func sampleGPUUsage(matchingClass className: String) -> Double? {
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

    func copyProperties(for service: io_object_t) -> MetricsDictionary? {
        var rawProperties: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &rawProperties, kCFAllocatorDefault, 0)
        guard status == KERN_SUCCESS, let rawProperties else { return nil }
        return rawProperties.takeRetainedValue() as? MetricsDictionary
    }
}

let ioMainPort: mach_port_t = kIOMainPortDefault
