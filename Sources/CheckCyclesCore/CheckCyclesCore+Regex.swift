import Foundation

extension CheckCyclesCore {
    static func markTargetsSection(_ line: String, inTargets: inout Bool) -> Bool {
        guard line.hasPrefix("targets:") else { return false }
        inTargets = true
        return true
    }

    static func leaveTargetsIfLetter(
        _ line: String,
        inTargets: inout Bool,
        currentTarget: inout String?,
        inDependencies: inout Bool
    ) {
        guard inTargets, let first = line.first, first.isLetter else { return }
        inTargets = false
        currentTarget = nil
        inDependencies = false
    }

    static func leaveDependencyBlockIfNeeded(_ line: String, inDependencies: inout Bool) {
        guard inDependencies else { return }
        if line.hasPrefix("    "), !line.hasPrefix("      "), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            inDependencies = false
        }
    }

    static func firstCapture(_ regex: NSRegularExpression, in line: String) -> String? {
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: full),
              match.numberOfRanges == 2,
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        return String(line[range])
    }
}
