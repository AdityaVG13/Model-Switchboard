import Foundation
import Testing
import ModelSwitchboardCore
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardApp

@MainActor
@Test func remoteSubtitleUsesVRAMWhenPresent() {
    let withVRAM = ModelFixtures.profileStatus(profile: "big", rssMB: 2200, vramMB: 55296)
    #expect(withVRAM.vramMB == 55296)
    #expect(String(format: "%.1f GB VRAM", (withVRAM.vramMB ?? 0) / 1024) == "54.0 GB VRAM")
    #expect(withVRAM.stateDescription.contains("VRAM"))
}
