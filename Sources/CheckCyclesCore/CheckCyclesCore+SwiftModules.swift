import Foundation

extension CheckCyclesCore {
    static func swiftModuleNames(at sourcesRoot: URL, fileManager: FileManager) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: sourcesRoot.path).filter { name in
            var isDir: ObjCBool = false
            return fileManager.fileExists(
                atPath: sourcesRoot.appendingPathComponent(name).path,
                isDirectory: &isDir
            ) && isDir.boolValue
        }
    }

    static func collectSwiftImports(
        module: String,
        moduleDir: URL,
        moduleSet: Set<String>,
        importRE: NSRegularExpression,
        fileManager: FileManager,
        graph: inout DependencyGraph
    ) throws {
        guard let enumerator = fileManager.enumerator(at: moduleDir, includingPropertiesForKeys: nil) else { return }
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
                guard let imported = firstCapture(importRE, in: line) else { continue }
                if moduleSet.contains(imported), imported != module {
                    graph[module, default: []].insert(imported)
                }
            }
        }
    }
}
