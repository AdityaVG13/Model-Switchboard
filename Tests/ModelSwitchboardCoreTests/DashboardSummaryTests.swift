import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func summaryChoosesBenchmarkLabel() {
    let payload = ModelFixtures.statusPayload(
        statuses: [ModelFixtures.profileStatus()],
        benchmark: BenchmarkStatus(running: true, pid: 42, logPath: "/tmp/bench.log", latest: nil)
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarTitle == "Bench 1/1")
    #expect(summary.menuBarSystemImage == "speedometer")
}

@Test func summaryUsesReadyLabelWhenNotBenchmarking() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(
                profile: "gemma",
                displayName: "Gemma",
                port: "8082",
                baseURL: "http://127.0.0.1:8082/v1",
                pid: nil,
                running: false,
                ready: true,
                rssMB: nil
            )
        ]
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarTitle == "Ready 1/1")
    #expect(summary.menuBarSystemImage == "memorychip.fill")
}

@Test func summaryUsesChipOutlineWhileStarting() {
    let payload = ModelFixtures.statusPayload(
        statuses: [
            ModelFixtures.profileStatus(
                pid: 123,
                running: true,
                ready: false,
                rssMB: nil
            )
        ]
    )
    let summary = DashboardSummary(payload: payload)
    #expect(summary.menuBarSystemImage == "memorychip")
}
