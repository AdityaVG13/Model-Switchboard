import Foundation
import ModelSwitchboardCore
import OSLog

extension RemoteAgentDeployer {
    static func bundledResource(_ name: String) -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RemoteAgent")
            .appendingPathComponent(name)
    }

    nonisolated var resourcesAvailable: Bool {
        FileManager.default.isReadableFile(atPath: agentSourceURL.path)
            && FileManager.default.isReadableFile(atPath: coreSourceURL.path)
            && FileManager.default.isReadableFile(atPath: discoverySourceURL.path)
            && FileManager.default.isReadableFile(atPath: installerURL.path)
    }
}
