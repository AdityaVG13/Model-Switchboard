import Darwin
import Foundation
import ModelSwitchboardCore

extension ControllerServiceManager {
    func migrateLegacyProfilesIfNeeded(to destination: URL) throws {
        let activeProfiles = profileFiles(in: destination)
        guard activeProfiles.isEmpty else { return }

        for legacyProfiles in legacyProfileDirectories() {
            guard fileManager.fileExists(atPath: legacyProfiles.path) else { continue }
            let sources = profileFiles(in: legacyProfiles)
            guard !sources.isEmpty else { continue }
            for source in sources {
                let target = destination.appendingPathComponent(source.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) { continue }
                try fileManager.copyItem(at: source, to: target)
            }
            Self.logger.info(
                "Migrated \(sources.count) profile(s) from \(legacyProfiles.path, privacy: .public)"
            )
            return
        }
    }

    func profileFiles(in directory: URL) -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { ["env", "json"].contains($0.pathExtension.lowercased()) } ?? []
    }

    /// Only the last known controller root from status cache -- no machine-specific home layouts.
    func legacyProfileDirectories() -> [URL] {
        guard let cachedRoot = ControllerStatusCache.load()?.controllerRoot else { return [] }
        return [
            URL(fileURLWithPath: cachedRoot).appendingPathComponent("model-profiles", isDirectory: true)
        ]
    }
}
