import Foundation
import Darwin

@MainActor
final class SystemMetricsMonitor: ObservableObject {
    @Published var cpuUsagePercent: Double?
    @Published var memoryUsagePercent: Double?
    @Published var gpuUsagePercent: Double?
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var gpuHistory: [Double] = []

    static let historyLimit = 16

    struct CPUSample {
        let totalTicks: UInt64
        let idleTicks: UInt64
    }

    typealias MetricsDictionary = [String: AnyObject]

    private var timer: Timer?
    var previousCPUSample: CPUSample?

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
}
