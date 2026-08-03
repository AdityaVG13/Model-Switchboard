import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

private func sparkMetrics(
    gpuUtil: Double = 42,
    vramUsed: Double = 55296,
    vramTotal: Double = 131072,
    processPID: Int? = 4242,
    processVRAM: Double? = 54000
) -> HostMetricsPayload {
    HostMetricsPayload(
        host: "spark",
        collectedAt: "2026-08-03T17:00:00Z",
        cpuPercent: 18,
        memory: HostMemoryMetrics(usedMB: 32000, totalMB: 128000, percent: 25, source: "proc"),
        gpus: [
            HostGPUMetrics(
                index: 0,
                name: "NVIDIA GB10",
                utilPercent: gpuUtil,
                tempC: 51,
                vramUsedMB: vramUsed,
                vramTotalMB: vramTotal
            )
        ],
        gpuSource: "nvidia-smi",
        processes: processPID.map { [HostGPUProcess(pid: $0, vramMB: processVRAM)] } ?? [],
        agentVersion: "1.1.2"
    )
}

@Test func compactGPUStripUsesHostVRAMNotRSS() {
    let metrics = sparkMetrics()
    let strip = HostMetricsPresentation.compactGPUStrip(metrics)
    #expect(strip == "GPU 42% · 54/128 GB VRAM · 51°C")
    #expect(strip?.contains("RSS") != true)
}

@Test func profileMemoryPrefersStatusVRAMThenProcessMapNeverBareRSSAsVRAM() {
    let metrics = sparkMetrics(processPID: 99, processVRAM: 54000)
    let withStatusVRAM = ModelFixtures.profileStatus(profile: "a", pid: 99, rssMB: 2200, vramMB: 55296)
    #expect(
        HostMetricsPresentation.profileMemoryLabel(status: withStatusVRAM, metrics: metrics, isRunning: true)
            == "54.0 GB VRAM"
    )

    let rssOnlyButProcessKnown = ModelFixtures.profileStatus(profile: "b", pid: 99, rssMB: 2200, vramMB: nil)
    #expect(
        HostMetricsPresentation.profileMemoryLabel(status: rssOnlyButProcessKnown, metrics: metrics, isRunning: true)
            == "52.7 GB VRAM"
    )

    let rssOnly = ModelFixtures.profileStatus(profile: "c", pid: 1, rssMB: 2200, vramMB: nil)
    let label = HostMetricsPresentation.profileMemoryLabel(status: rssOnly, metrics: metrics, isRunning: true)
    #expect(label == "2.1 GB RSS")
    #expect(label?.contains("VRAM") != true)
}

@Test func hostVRAMPercentAndChip() {
    let metrics = sparkMetrics()
    #expect(HostMetricsPresentation.hostVRAMPercent(metrics).map { Int($0.rounded()) } == 42)
    #expect(HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics) == "54/128 GB")
    #expect(HostMetricsPresentation.sectionMetricsChip(metrics)?.contains("VRAM") == true)
}

@Test func missingMetricsYieldNilNotFakeVRAM() {
    #expect(HostMetricsPresentation.compactGPUStrip(nil) == nil)
    let status = ModelFixtures.profileStatus(profile: "x", running: false, ready: false, rssMB: nil, vramMB: nil)
    #expect(
        HostMetricsPresentation.profileMemoryLabel(status: status, metrics: nil, isRunning: false) == nil
    )
}
