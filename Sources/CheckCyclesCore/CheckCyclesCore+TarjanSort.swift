import Foundation

extension CheckCyclesCore {
    static func sortedCycles(sccs: [[String]], graph: DependencyGraph) -> [[String]] {
        var cycles = sccs.filter { $0.count > 1 }.map { $0.sorted() }
        cycles.append(contentsOf: selfLoops(in: graph))
        return cycles.sorted(by: cycleOrder)
    }

    static func selfLoops(in graph: DependencyGraph) -> [[String]] {
        graph.compactMap { node, neighbors in
            neighbors.contains(node) ? [node] : nil
        }
    }

    static func cycleOrder(_ lhs: [String], _ rhs: [String]) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count < rhs.count
        }
        return lhs.lexicographicallyPrecedes(rhs)
    }
}
