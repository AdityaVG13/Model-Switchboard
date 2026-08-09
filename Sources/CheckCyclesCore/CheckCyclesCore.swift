import Foundation

public typealias DependencyGraph = [String: Set<String>]

public enum CheckCyclesCore {
    public static func tarjanCycles(_ graph: DependencyGraph) -> [[String]] {
        var index = 0
        var indices: [String: Int] = [:]
        var lowlink: [String: Int] = [:]
        var stack: [String] = []
        var onStack: Set<String> = []
        var sccs: [[String]] = []

        func strongconnect(_ node: String) {
            indices[node] = index
            lowlink[node] = index
            index += 1
            stack.append(node)
            onStack.insert(node)

            for neighbor in graph[node, default: []] {
                if indices[neighbor] == nil {
                    strongconnect(neighbor)
                    lowlink[node] = min(lowlink[node]!, lowlink[neighbor]!)
                } else if onStack.contains(neighbor) {
                    lowlink[node] = min(lowlink[node]!, indices[neighbor]!)
                }
            }

            if lowlink[node] == indices[node] {
                var component: [String] = []
                while !stack.isEmpty {
                    let popped = stack.removeLast()
                    onStack.remove(popped)
                    component.append(popped)
                    if popped == node {
                        break
                    }
                }
                sccs.append(component)
            }
        }

        for node in graph.keys.sorted() {
            if indices[node] == nil {
                strongconnect(node)
            }
        }

        var cycles = sccs.filter { $0.count > 1 }.map { $0.sorted() }
        for (node, neighbors) in graph {
            if neighbors.contains(node) {
                cycles.append([node])
            }
        }
        return cycles.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count < rhs.count
            }
            return lhs.lexicographicallyPrecedes(rhs)
        }
    }

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
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw CheckCyclesError.commandFailed("swift package describe", err)
        }
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

    public static func parseXcodeTargetGraph(projectYML: String) -> DependencyGraph {
        let lines = projectYML.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var graph: DependencyGraph = [:]
        var inTargets = false
        var currentTarget: String?
        var inDependencies = false

        let targetDecl = try! NSRegularExpression(pattern: #"^  ([A-Za-z0-9_+.-]+):\s*$"#)
        let targetDep = try! NSRegularExpression(pattern: #"^      - target:\s*([A-Za-z0-9_+.-]+)\s*$"#)

        for line in lines {
            if line.hasPrefix("targets:") {
                inTargets = true
                continue
            }

            if inTargets, let first = line.first, first.isLetter {
                inTargets = false
                currentTarget = nil
                inDependencies = false
            }

            if !inTargets {
                continue
            }

            let nsLine = line as NSString
            let full = NSRange(location: 0, length: nsLine.length)
            if let match = targetDecl.firstMatch(in: line, options: [], range: full),
               match.numberOfRanges == 2,
               let nameRange = Range(match.range(at: 1), in: line)
            {
                currentTarget = String(line[nameRange])
                graph[currentTarget!, default: []] = []
                inDependencies = false
                continue
            }

            guard let currentTarget else { continue }

            if line.hasPrefix("    dependencies:") {
                inDependencies = true
                continue
            }

            if inDependencies {
                if line.hasPrefix("    "), !line.hasPrefix("      "), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    inDependencies = false
                }
            }

            if inDependencies,
               let match = targetDep.firstMatch(in: line, options: [], range: full),
               match.numberOfRanges == 2,
               let depRange = Range(match.range(at: 1), in: line)
            {
                graph[currentTarget, default: []].insert(String(line[depRange]))
            }
        }

        let known = Set(graph.keys)
        return graph.mapValues { Set($0.filter { known.contains($0) }) }
    }

    public static func parseSwiftModuleGraph(sourcesRoot: URL) throws -> DependencyGraph {
        let fm = FileManager.default
        let modules = try fm.contentsOfDirectory(atPath: sourcesRoot.path).filter { name in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: sourcesRoot.appendingPathComponent(name).path, isDirectory: &isDir) && isDir.boolValue
        }
        let moduleSet = Set(modules)
        var graph: DependencyGraph = Dictionary(uniqueKeysWithValues: modules.map { ($0, Set<String>()) })
        let importRE = try NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)"#)

        for module in modules {
            let moduleDir = sourcesRoot.appendingPathComponent(module)
            guard let enumerator = fm.enumerator(at: moduleDir, includingPropertiesForKeys: nil) else { continue }
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                    let nsLine = line as NSString
                    let full = NSRange(location: 0, length: nsLine.length)
                    guard let match = importRE.firstMatch(in: line, options: [], range: full),
                          match.numberOfRanges == 2,
                          let nameRange = Range(match.range(at: 1), in: line)
                    else { continue }
                    let imported = String(line[nameRange])
                    if moduleSet.contains(imported), imported != module {
                        graph[module, default: []].insert(imported)
                    }
                }
            }
        }
        return graph
    }

    public static func printGraph(_ title: String, _ graph: DependencyGraph) {
        print("\n\(title)")
        for node in graph.keys.sorted() {
            let neighbors = graph[node, default: []].sorted().joined(separator: ", ")
            print("  \(node) -> \(neighbors.isEmpty ? "(none)" : neighbors)")
        }
    }

    public static func ensureAcyclic(name: String, graph: DependencyGraph) -> Bool {
        let cycles = tarjanCycles(graph)
        if !cycles.isEmpty {
            print("\n\(name): CYCLES DETECTED")
            for cyc in cycles {
                print("  cycle: \(cyc.joined(separator: " -> "))")
            }
            return false
        }
        print("\n\(name): no cycles")
        return true
    }
}

public enum CheckCyclesError: Error, CustomStringConvertible {
    case commandFailed(String, String)
    case invalidSPMDescribe
    case missingProjectYML(String)

    public var description: String {
        switch self {
        case .commandFailed(let cmd, let stderr):
            return "\(cmd) failed: \(stderr)"
        case .invalidSPMDescribe:
            return "invalid swift package describe JSON"
        case .missingProjectYML(let path):
            return "missing required file: \(path)"
        }
    }
}
