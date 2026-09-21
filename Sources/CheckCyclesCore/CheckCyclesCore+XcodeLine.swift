import Foundation

extension CheckCyclesCore {
    static func applyXcodeLine(
        _ line: String,
        inTargets: inout Bool,
        currentTarget: inout String?,
        inDependencies: inout Bool,
        graph: inout DependencyGraph,
        targetDecl: NSRegularExpression,
        targetDep: NSRegularExpression
    ) {
        if markTargetsSection(line, inTargets: &inTargets) { return }
        leaveTargetsIfLetter(
            line,
            inTargets: &inTargets,
            currentTarget: &currentTarget,
            inDependencies: &inDependencies
        )
        guard inTargets else { return }

        if let name = firstCapture(targetDecl, in: line) {
            currentTarget = name
            graph[name, default: []] = []
            inDependencies = false
            return
        }

        guard let currentTarget else { return }

        if line.hasPrefix("    dependencies:") {
            inDependencies = true
            return
        }

        leaveDependencyBlockIfNeeded(line, inDependencies: &inDependencies)
        if inDependencies, let dep = firstCapture(targetDep, in: line) {
            graph[currentTarget, default: []].insert(dep)
        }
    }
}
