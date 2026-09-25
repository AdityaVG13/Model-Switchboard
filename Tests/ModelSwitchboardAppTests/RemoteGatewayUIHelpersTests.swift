import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

@MainActor
@Test func remoteSubtitleUsesVRAMWhenPresent() {
    // VRAM wins over RSS on a healthy row.
    let withVRAM = ModelFixtures.profileStatus(profile: "big", rssMB: 2200, vramMB: 55296)
    #expect(withVRAM.stateDescription == "llama.cpp • Running • endpoint healthy • 55296.0 MB VRAM")

    // RSS is the fallback while the endpoint is still pending.
    let warming = ModelFixtures.profileStatus(profile: "warming", running: true, ready: false, rssMB: 2200)
    #expect(warming.stateDescription == "llama.cpp • Starting • endpoint pending • 2200.0 MB RSS")

    // Stopped rows carry no memory part at all.
    let stopped = ModelFixtures.profileStatus(profile: "idle", running: false, ready: false)
    #expect(stopped.stateDescription == "llama.cpp • Not Running")
}
