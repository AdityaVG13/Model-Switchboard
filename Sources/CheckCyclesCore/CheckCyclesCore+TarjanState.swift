import Foundation

extension CheckCyclesCore {
    struct TarjanState {
        var index = 0
        var indices: [String: Int] = [:]
        var lowlink: [String: Int] = [:]
        var stack: [String] = []
        var onStack: Set<String> = []
        var sccs: [[String]] = []
    }
}
