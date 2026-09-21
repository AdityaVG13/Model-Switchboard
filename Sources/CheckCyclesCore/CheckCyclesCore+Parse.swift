import Foundation

extension CheckCyclesCore {
    public static func parseSwiftModuleGraph(sourcesRoot: URL) throws -> DependencyGraph {
        let fileManager = FileManager.default
        let modules = try swiftModuleNames(at: sourcesRoot, fileManager: fileManager)
        let moduleSet = Set(modules)
        var graph: DependencyGraph = Dictionary(uniqueKeysWithValues: modules.map { ($0, Set<String>()) })
        let importRE = try NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)"#)

        for module in modules {
            try collectSwiftImports(
                module: module,
                moduleDir: sourcesRoot.appendingPathComponent(module),
                moduleSet: moduleSet,
                importRE: importRE,
                fileManager: fileManager,
                graph: &graph
            )
        }
        return graph
    }
}
