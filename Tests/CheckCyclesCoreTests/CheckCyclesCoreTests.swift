import Testing
@testable import CheckCyclesCore

@Test func tarjanFindsMultiNodeCycle() {
    let graph: DependencyGraph = [
        "A": ["B"],
        "B": ["C"],
        "C": ["A"],
        "D": ["E"],
        "E": [],
    ]
    let cycles = CheckCyclesCore.tarjanCycles(graph)
    #expect(cycles == [["A", "B", "C"]])
}

@Test func tarjanFindsSelfLoop() {
    let graph: DependencyGraph = [
        "Solo": ["Solo"],
        "Other": [],
    ]
    let cycles = CheckCyclesCore.tarjanCycles(graph)
    #expect(cycles == [["Solo"]])
}

@Test func tarjanReportsAcyclic() {
    let graph: DependencyGraph = [
        "A": ["B"],
        "B": ["C"],
        "C": [],
    ]
    #expect(CheckCyclesCore.tarjanCycles(graph).isEmpty)
}
