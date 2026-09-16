import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

private func payload(
    host: String? = nil,
    collectedAt: String? = nil,
    cpuPercent: Double? = nil,
    memory: HostMemoryMetrics? = nil,
    gpus: [HostGPUMetrics] = [],
    gpuSource: GPUSource? = nil,
    processes: [HostGPUProcess] = [],
    agentVersion: String? = nil,
    uptimeSeconds: Double? = nil,
    storage: HostStorageMetrics? = nil,
    network: HostNetworkMetrics? = nil,
    tailscale: TailnetHealth? = nil
) -> HostMetricsPayload {
    HostMetricsPayload(
        host: host,
        collectedAt: collectedAt,
        cpuPercent: cpuPercent,
        memory: memory,
        gpus: gpus,
        gpuSource: gpuSource,
        processes: processes,
        agentVersion: agentVersion,
        uptimeSeconds: uptimeSeconds,
        storage: storage,
        network: network,
        tailscale: tailscale
    )
}

private func sparkMetrics(
    gpuUtil: Double = 42,
    vramUsed: Double = 55296,
    vramTotal: Double = 131072,
    processPID: Int? = 4242,
    processVRAM: Double? = 54000
) -> HostMetricsPayload {
    payload(
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
        gpuSource: .nvidiaSmi,
        processes: processPID.map { [HostGPUProcess(pid: $0, vramMB: processVRAM)] } ?? [],
        agentVersion: "1.1.2",
        uptimeSeconds: nil,
        storage: nil,
        network: nil,
        tailscale: nil
    )
}

@Test func compactGPUStripUsesHostVRAMNotRSS() {
    let metrics = sparkMetrics()
    let strip = HostMetricsPresentation.compactGPUStrip(metrics)
    #expect(strip == "GPU 42% · 54.0/128.0 GB · 51°C")
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
    #expect(HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics) == "54.0/128.0 GB")
    #expect(HostMetricsPresentation.sectionMetricsChip(metrics)?.contains("54.0/128.0 GB") == true)
}

@Test func gb10VRAMLabelMatchesDashboardGiBNotHostRAMUsed() {
    // nvidia-smi compute-apps sum 26009.6 MiB / MemTotal 124620.8 MiB → SparkDash 25.4/121.7.
    // Host RAM "used" (~34816 MiB → 34 GB) must not appear on the chip.
    let metrics = sparkMetrics(vramUsed: 26009.6, vramTotal: 124620.8)
    #expect(HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics) == "25.4/121.7 GB")
    #expect(HostMetricsPresentation.hostVRAMUsedTotalLabel(metrics) != "34.0/121.7 GB")
    #expect(HostMetricsPresentation.compactGPUStrip(metrics) == "GPU 42% · 25.4/121.7 GB · 51°C")
}

@Test func missingMetricsYieldNilNotFakeVRAM() {
    #expect(HostMetricsPresentation.compactGPUStrip(nil) == nil)
    let status = ModelFixtures.profileStatus(profile: "x", running: false, ready: false, rssMB: nil, vramMB: nil)
    #expect(
        HostMetricsPresentation.profileMemoryLabel(status: status, metrics: nil, isRunning: false) == nil
    )
}

@MainActor
@Test func dashPresentationLabels() {
    let storage = HostStorageMetrics(usedMB: 422_296.6, totalMB: 1_875_335.2, percent: 22.5, source: "statvfs")
    let network = HostNetworkMetrics(rxKbps: 1240.5, txKbps: 310.2, source: "proc")
    let healthyTailnet = TailnetHealth(
        online: true,
        backendState: "Running",
        ipv4: "100.64.1.2",
        dnsName: nil,
        health: []
    )
    let uptime: Double = 3 * 86400 + 4 * 3600 + 5 * 60
    let metrics = payload(
        host: nil,
        collectedAt: nil,
        cpuPercent: nil,
        memory: nil,
        gpus: [],
        gpuSource: nil,
        processes: [],
        agentVersion: nil,
        uptimeSeconds: uptime,
        storage: storage,
        network: network,
        tailscale: healthyTailnet
    )
    #expect(HostMetricsPresentation.uptimeLabel(metrics) == "up 3d 4h")
    #expect(HostMetricsPresentation.storageLabel(metrics) == "412.4/1831.4 GB")
    #expect(HostMetricsPresentation.networkLabel(metrics) == "↓ 1.2 · ↑ 0.3 MB/s")
    let tailnet = HostMetricsPresentation.tailnetLabel(metrics)
    #expect(tailnet?.label == "TAILNET OK")
    #expect(tailnet?.detail == "100.64.1.2")

    let offline = payload(
        host: nil,
        collectedAt: nil,
        cpuPercent: nil,
        memory: nil,
        gpus: [],
        gpuSource: nil,
        processes: [],
        agentVersion: nil,
        uptimeSeconds: nil,
        storage: nil,
        network: nil,
        tailscale: TailnetHealth(
            online: false,
            backendState: "NeedsLogin",
            ipv4: nil,
            dnsName: nil,
            health: ["login expired"]
        )
    )
    #expect(HostMetricsPresentation.tailnetLabel(offline)?.label == "TAILNET OFF")

    let warned = payload(
        host: nil,
        collectedAt: nil,
        cpuPercent: nil,
        memory: nil,
        gpus: [],
        gpuSource: nil,
        processes: [],
        agentVersion: nil,
        uptimeSeconds: nil,
        storage: nil,
        network: nil,
        tailscale: TailnetHealth(
            online: true,
            backendState: "Running",
            ipv4: nil,
            dnsName: nil,
            health: ["derp relay issue"]
        )
    )
    #expect(HostMetricsPresentation.tailnetLabel(warned)?.label == "TAILNET WARN")

    #expect(HostMetricsPresentation.uptimeLabel(nil) == nil)
    #expect(
        HostMetricsPresentation.tailnetLabel(
            payload(
                host: nil,
                collectedAt: nil,
                cpuPercent: nil,
                memory: nil,
                gpus: [],
                gpuSource: nil,
                processes: [],
                agentVersion: nil,
                uptimeSeconds: nil,
                storage: nil,
                network: nil,
                tailscale: nil
            )
        ) == nil
    )
}

@MainActor
@Test func servingRateLabelFormats() {
    func status(_ tokS: Double?) -> ModelProfileStatus {
        ModelProfileStatus(
            profile: "p", displayName: "P", runtime: "vllm", host: "127.0.0.1", port: "8050",
            baseURL: "http://127.0.0.1:8050/v1", requestModel: "m", serverModelID: "m",
            pid: 1, running: true, ready: true, serverIDs: [], rssMB: nil,
            command: nil,
            serving: tokS.map { ServingMetrics(backend: "vllm", tokS: $0) }
        )
    }
    #expect(HostMetricsPresentation.servingRateLabel(status(42.31)) == "42.3 tok/s")
    #expect(HostMetricsPresentation.servingRateLabel(status(123.4)) == "123 tok/s")
    #expect(HostMetricsPresentation.servingRateLabel(status(0)) == nil)
    #expect(HostMetricsPresentation.servingRateLabel(status(nil)) == nil)
}
