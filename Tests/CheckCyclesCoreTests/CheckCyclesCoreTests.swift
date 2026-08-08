import Testing
import CheckCyclesCore

@Test func tarjanCyclesFindsMultiNodeCycle() {
    let graph: [String: Set<String>] = [
        "A": ["B"],
        "B": ["C"],
        "C": ["A"],
        "D": [],
    ]
    let cycles = CheckCyclesCore.tarjanCycles(graph)
    #expect(cycles == [["A", "B", "C"]])
}

@Test func tarjanCyclesFindsSelfLoop() {
    let graph: [String: Set<String>] = [
        "A": ["A"],
        "B": [],
    ]
    #expect(CheckCyclesCore.tarjanCycles(graph) == [["A"]])
}
