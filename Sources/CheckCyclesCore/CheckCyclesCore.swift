import Foundation

public typealias DependencyGraph = [String: Set<String>]

public enum CheckCyclesCore {
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
