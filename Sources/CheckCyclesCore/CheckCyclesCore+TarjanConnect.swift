import Foundation

extension CheckCyclesCore {
    static func connectUnvisited(_ graph: DependencyGraph, state: inout TarjanState) {
        for node in graph.keys.sorted() where state.indices[node] == nil {
            strongconnect(node, graph: graph, state: &state)
        }
    }

    static func strongconnect(_ node: String, graph: DependencyGraph, state: inout TarjanState) {
        state.indices[node] = state.index
        state.lowlink[node] = state.index
        state.index += 1
        state.stack.append(node)
        state.onStack.insert(node)

        for neighbor in graph[node, default: []] {
            visitNeighbor(neighbor, node: node, graph: graph, state: &state)
        }
        popSCC(node: node, state: &state)
    }

    static func visitNeighbor(
        _ neighbor: String,
        node: String,
        graph: DependencyGraph,
        state: inout TarjanState
    ) {
        if state.indices[neighbor] == nil {
            strongconnect(neighbor, graph: graph, state: &state)
            adoptLowlink(node, from: state.lowlink[neighbor]!, state: &state)
        } else if state.onStack.contains(neighbor) {
            adoptLowlink(node, from: state.indices[neighbor]!, state: &state)
        }
    }

    static func adoptLowlink(_ node: String, from other: Int, state: inout TarjanState) {
        state.lowlink[node] = min(state.lowlink[node]!, other)
    }

    static func popSCC(node: String, state: inout TarjanState) {
        guard state.lowlink[node] == state.indices[node] else { return }
        var component: [String] = []
        while !state.stack.isEmpty {
            let popped = state.stack.removeLast()
            state.onStack.remove(popped)
            component.append(popped)
            if popped == node { break }
        }
        state.sccs.append(component)
    }
}
