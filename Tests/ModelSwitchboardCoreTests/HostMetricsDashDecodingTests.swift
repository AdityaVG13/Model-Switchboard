import Foundation
import Testing
import ModelSwitchboardCore
@testable import ModelSwitchboardApp

/// Additive wire decode: new sparkDash-derived fields on /api/host/metrics and
/// status rows, plus tolerance of old-agent payloads that omit them entirely.
@Test func hostMetricsDecodesNewDashFields() throws {
    let json = """
    {
      "host": "spark",
      "cpu_percent": 12.5,
      "memory": {"used_mb": 1000, "total_mb": 2000, "percent": 50.0, "source": "proc"},
      "gpus": [{"index": 0, "name": "GB10", "util_percent": 3, "temp_c": 41,
                "vram_used_mb": 52.1, "vram_total_mb": 121.7}],
      "processes": [{"pid": 123, "vram_mb": 1000.5, "name": "vllm"}],
      "uptime_seconds": 262974.0,
      "storage": {"used_mb": 422296.6, "total_mb": 1875335.2, "percent": 22.5, "source": "statvfs"},
      "network": {"rx_kbps": 1240.5, "tx_kbps": 310.2, "source": "proc"},
      "tailscale": {"online": true, "backend_state": "Running",
                    "ipv4": "100.122.96.76", "dns_name": "dgx-spark.tail01763b.ts.net",
                    "health": []},
      "agent_version": "1.2.0"
    }
    """
    let payload = try JSONDecoder().decode(HostMetricsPayload.self, from: Data(json.utf8))
    #expect(payload.uptimeSeconds == 262974.0)
    #expect(payload.storage?.percent == 22.5)
    #expect(payload.network?.rxKbps == 1240.5)
    #expect(payload.tailscale?.online == true)
    #expect(payload.tailscale?.ipv4 == "100.122.96.76")
    #expect(payload.processes.first?.name == "vllm")
}

@Test func hostMetricsToleratesOldAgentWithoutDashFields() throws {
    let json = """
    {"host": "old-host", "cpu_percent": 5.0, "gpus": [], "processes": [], "agent_version": "1.1.3"}
    """
    let payload = try JSONDecoder().decode(HostMetricsPayload.self, from: Data(json.utf8))
    #expect(payload.uptimeSeconds == nil)
    #expect(payload.storage == nil)
    #expect(payload.network == nil)
    #expect(payload.tailscale == nil)
    #expect(payload.processes.isEmpty)
}

@Test func servingMetricsDecodesAndToleratesOmission() throws {
    let json = """
    {"profile": "port-8050", "display_name": "balesh-parent-A", "runtime": "vllm",
     "host": "127.0.0.1", "port": "8050", "base_url": "http://127.0.0.1:8050/v1",
     "request_model": "balesh-parent-A", "server_model_id": "balesh-parent-A",
     "running": true, "ready": true, "server_ids": ["balesh-parent-A"],
     "serving": {"backend": "vllm", "tok_s": 42.31, "prompt_tok_s": 900.5,
                 "kv_cache_usage": 0.12, "requests_running": 1.0, "requests_waiting": 0.0}}
    """
    let status = try JSONDecoder().decode(ModelProfileStatus.self, from: Data(json.utf8))
    #expect(status.serving?.backend == "vllm")
    #expect(status.serving?.tokS == 42.31)
    #expect(status.serving?.kvCacheUsage == 0.12)

    // Old agents omit `serving` entirely.
    let legacyJSON = """
    {"profile": "p", "display_name": "P", "runtime": "vllm", "host": "127.0.0.1",
     "port": "8050", "base_url": "http://127.0.0.1:8050/v1", "request_model": "m",
     "server_model_id": "m", "running": false, "ready": false, "server_ids": []}
    """
    let legacy = try JSONDecoder().decode(ModelProfileStatus.self, from: Data(legacyJSON.utf8))
    #expect(legacy.serving == nil)
}

@MainActor
@Test func dashPresentationLabels() {
    let metrics = HostMetricsPayload(
        uptimeSeconds: 3 * 86400 + 4 * 3600 + 5 * 60,
        storage: HostStorageMetrics(usedMB: 422_296.6, totalMB: 1_875_335.2, percent: 22.5, source: "statvfs"),
        network: HostNetworkMetrics(rxKbps: 1240.5, txKbps: 310.2, source: "proc"),
        tailscale: TailnetHealth(online: true, backendState: "Running", ipv4: "100.122.96.76", dnsName: nil, health: [])
    )
    #expect(HostMetricsPresentation.uptimeLabel(metrics) == "up 3d 4h")
    #expect(HostMetricsPresentation.storageLabel(metrics) == "412.4/1831.4 GB")
    #expect(HostMetricsPresentation.networkLabel(metrics) == "↓ 1.2 · ↑ 0.3 MB/s")
    let tailnet = HostMetricsPresentation.tailnetLabel(metrics)
    #expect(tailnet?.label == "TAILNET OK")
    #expect(tailnet?.detail == "100.122.96.76")

    // Offline + warning states surface, not hide.
    let offline = HostMetricsPayload(
        tailscale: TailnetHealth(online: false, backendState: "NeedsLogin", ipv4: nil, dnsName: nil, health: ["login expired"])
    )
    #expect(HostMetricsPresentation.tailnetLabel(offline)?.label == "TAILNET OFF")

    let warned = HostMetricsPayload(
        tailscale: TailnetHealth(online: true, backendState: "Running", ipv4: nil, dnsName: nil, health: ["derp relay issue"])
    )
    #expect(HostMetricsPresentation.tailnetLabel(warned)?.label == "TAILNET WARN")

    // No data -> no label (graceful degradation).
    #expect(HostMetricsPresentation.uptimeLabel(nil) == nil)
    #expect(HostMetricsPresentation.tailnetLabel(HostMetricsPayload()) == nil)
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
