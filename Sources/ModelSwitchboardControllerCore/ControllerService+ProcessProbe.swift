import Foundation
import ModelSwitchboardCore

extension ControllerService {
    func listenerPID(port: String) -> Int? {
        guard !port.isEmpty,
            let result = try? ProcessRunner.run(
                "/usr/sbin/lsof", ["-tiTCP:\(port)", "-sTCP:LISTEN"], check: false)
        else { return nil }
        return result.stdout.split(whereSeparator: \.isNewline).compactMap { Int($0) }.first
    }

    func processCommand(_ pid: Int?) -> String? {
        guard let pid,
            let result = try? ProcessRunner.run(
                "/bin/ps", ["-o", "command=", "-p", String(pid)], check: false)
        else { return nil }
        return result.stdout.nonEmptyTrimmed
    }

    func rssMB(_ pid: Int?) -> Double? {
        guard let pid,
            let result = try? ProcessRunner.run(
                "/bin/ps", ["-o", "rss=", "-p", String(pid)], check: false),
            let rss = Double(result.stdout.trimmed)
        else { return nil }
        return (rss / 1024 * 10).rounded() / 10
    }

    func profileWorkingDirectory(_ profile: ControllerProfile) -> URL? {
        guard let raw = profile["WORKING_DIRECTORY"] ?? profile["WORKDIR"], !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
    }
}
