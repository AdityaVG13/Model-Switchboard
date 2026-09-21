import Foundation

extension CheckCyclesCore {
    public static func tarjanCycles(_ graph: DependencyGraph) -> [[String]] {
        var state = TarjanState()
        connectUnvisited(graph, state: &state)
        return sortedCycles(sccs: state.sccs, graph: graph)
    }
}
