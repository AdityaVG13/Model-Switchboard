import Foundation
import CheckCyclesCore

@main
struct CheckCyclesCommand {
    static func main() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        do {
            let projectPath = root.appendingPathComponent("project.yml")
            guard FileManager.default.isReadableFile(atPath: projectPath.path) else {
                fputs("missing required file: \(projectPath.path)\n", stderr)
                exit(1)
            }
            let projectText = try String(contentsOf: projectPath, encoding: .utf8)
            let graphs: [(String, DependencyGraph)] = [
                ("Swift module import graph", try CheckCyclesCore.parseSwiftModuleGraph(sourcesRoot: root.appendingPathComponent("Sources"))),
                ("Swift SPM target dependency graph", try CheckCyclesCore.parseSPMTargetGraph(root: root)),
                ("Swift Xcode target dependency graph", CheckCyclesCore.parseXcodeTargetGraph(projectYML: projectText)),
            ]
            var ok = true
            for (label, graph) in graphs {
                CheckCyclesCore.printGraph(label, graph)
                ok = CheckCyclesCore.ensureAcyclic(name: label, graph: graph) && ok
            }
            exit(ok ? 0 : 1)
        } catch let error as CheckCyclesError {
            fputs("\(error.description)\n", stderr)
            exit(1)
        } catch {
            fputs("\(error)\n", stderr)
            exit(1)
        }
    }
}
