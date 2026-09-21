import Foundation

extension CheckCyclesCore {
    public static func parseXcodeTargetGraph(projectYML: String) -> DependencyGraph {
        let lines = projectYML.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var graph: DependencyGraph = [:]
        var inTargets = false
        var currentTarget: String?
        var inDependencies = false

        let targetDecl = try! NSRegularExpression(pattern: #"^  ([A-Za-z0-9_+.-]+):\s*$"#)
        let targetDep = try! NSRegularExpression(pattern: #"^      - target:\s*([A-Za-z0-9_+.-]+)\s*$"#)

        for line in lines {
            applyXcodeLine(
                line,
                inTargets: &inTargets,
                currentTarget: &currentTarget,
                inDependencies: &inDependencies,
                graph: &graph,
                targetDecl: targetDecl,
                targetDep: targetDep
            )
        }

        let known = Set(graph.keys)
        return graph.mapValues { Set($0.filter { known.contains($0) }) }
    }
}
