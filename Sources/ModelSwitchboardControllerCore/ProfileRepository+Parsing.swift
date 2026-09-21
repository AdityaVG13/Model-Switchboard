import Foundation
import ModelSwitchboardCore

extension ProfileRepository {
    func parseEnvironment(_ file: URL) throws -> [String: String] {
        let content = try String(contentsOf: file, encoding: .utf8)
        var values: [String: String] = [:]
        for (offset, rawLine) in content.components(separatedBy: .newlines).enumerated() {
            var line = rawLine.whitespaceTrimmed
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst(7)).whitespaceTrimmed
            }
            guard let equals = line.firstIndex(of: "=") else {
                throw ControllerError.invalidProfile("\(file.path):\(offset + 1): expected KEY=value")
            }
            let key = String(line[..<equals]).whitespaceTrimmed
            try Self.requireProfileKey(key, file: file, line: offset + 1)
            let rawValue = String(line[line.index(after: equals)...]).whitespaceTrimmed
            values[key] = try parseValue(rawValue, file: file, line: offset + 1)
        }
        return values
    }

    static func requireProfileKey(_ key: String, file: URL, line: Int?) throws {
        guard isValidProfileKey(key) else {
            if let line {
                throw ControllerError.invalidProfile("\(file.path):\(line): invalid profile key \(key)")
            }
            throw ControllerError.invalidProfile("\(file.path): invalid profile key \(key)")
        }
    }

    static func isValidProfileKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }
}
