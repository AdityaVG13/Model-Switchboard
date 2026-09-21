import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func pidFile(_ name: String) -> URL {
        configuration.runDirectory.appendingPathComponent("\(name).pid")
    }

    func readPID(_ name: String) -> Int? {
        guard let value = try? String(contentsOf: pidFile(name), encoding: .utf8) else { return nil }
        return Int(value.trimmed)
    }
}
