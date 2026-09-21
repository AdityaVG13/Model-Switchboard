import Foundation

extension CheckCyclesCore {
    public static func parseSPMTargetGraph(root: URL) throws -> DependencyGraph {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "describe", "--type", "json"]
        process.currentDirectoryURL = root
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Drain pipes before waiting for exit (see ProcessRunner.run: wait-
        // then-read deadlocks once output exceeds the pipe buffer).
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CheckCyclesError.commandFailed("swift package describe", err)
        }
        return try graphFromSPMDescribe(data)
    }

    static func graphFromSPMDescribe(_ data: Data) throws -> DependencyGraph {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = json["targets"] as? [[String: Any]]
        else {
            throw CheckCyclesError.invalidSPMDescribe
        }
        let targetNames = Set(targets.compactMap { $0["name"] as? String })
        var graph: DependencyGraph = [:]
        for target in targets {
            guard let name = target["name"] as? String else { continue }
            let deps = Set((target["target_dependencies"] as? [String] ?? []).filter { targetNames.contains($0) })
            graph[name] = deps
        }
        return graph
    }
}
