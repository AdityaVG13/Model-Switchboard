import Foundation
import Testing
import ModelSwitchboardTestSupport
@testable import ModelSwitchboardCore

@Test func cacheRoundTripPreservesPayload() throws {
    let status = ModelFixtures.profileStatus(
        profile: "gemma",
        displayName: "Gemma",
        port: "8081",
        baseURL: "http://127.0.0.1:8081/v1",
        pid: nil,
        running: false,
        ready: false,
        rssMB: nil
    )
    let payload = ModelFixtures.statusPayload(
        statuses: [status],
        profilesDirectory: "/tmp/model-profiles",
        controllerRoot: "/tmp"
    )
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("json")

    try ControllerStatusCache.write(payload, cachedAt: Date(timeIntervalSince1970: 1_700_000_000), to: tempURL)
    let cached = try #require(ControllerStatusCache.load(from: tempURL))

    #expect(cached.payload == payload)
    #expect(cached.sourcePaths.profilesDirectory == "/tmp/model-profiles")
    #expect(cached.sourcePaths.controllerRoot == "/tmp")
}

@Test func sourcePathsAreSharedAcrossControllerPayloadTypes() {
    let statusPayload = ModelFixtures.statusPayload(
        statuses: [],
        benchmark: nil,
        profilesDirectory: "/tmp/profiles",
        controllerRoot: "/tmp/controller"
    )

    let actionPayload = ControllerActionResponse(
        ok: true,
        statuses: [],
        benchmark: nil,
        integrations: [],
        profilesDirectory: "/tmp/profiles",
        controllerRoot: "/tmp/controller",
        error: nil
    )

    #expect(statusPayload.sourcePaths == actionPayload.sourcePaths)
    #expect(statusPayload.sourcePaths.profilesDirectory == "/tmp/profiles")
    #expect(statusPayload.sourcePaths.controllerRoot == "/tmp/controller")
}
