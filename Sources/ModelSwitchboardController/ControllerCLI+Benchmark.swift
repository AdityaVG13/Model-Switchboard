import Foundation
import ModelSwitchboardControllerCore

extension ModelSwitchboardControllerMain {
    static func runBenchmark(_ arguments: [String], service: ControllerService) throws {
        let selected = option("--profiles", in: arguments)?.split(separator: ",").map(String.init)
        if isDryRun(arguments) {
            try printPlan(command: "benchmark", profiles: selected ?? [])
            return
        }
        let status = try service.benchmarks.start(
            profiles: selected,
            suite: option("--suite", in: arguments) ?? "quick",
            allowConcurrent: arguments.contains("--allow-concurrent"),
            keepRunning: arguments.contains("--keep-running")
        )
        try printJSON(status)
    }

    static func runBenchmarkWorker(_ arguments: [String], service: ControllerService) throws {
        let selected = option("--profiles", in: arguments)?.split(separator: ",").map(String.init)
        try service.benchmarks.runWorker(
            selectedNames: selected,
            suite: option("--suite", in: arguments) ?? "quick",
            allowConcurrent: arguments.contains("--allow-concurrent"),
            keepRunning: arguments.contains("--keep-running")
        )
    }

    static func runProfileExports(_ arguments: [String], service: ControllerService) throws {
        guard let path = option("--profile-file", in: arguments) else {
            throw ControllerError.usage("missing value for --profile-file")
        }
        let profile = try service.profiles.load(file: URL(fileURLWithPath: path))
        for key in profile.values.keys.sorted() {
            print("export \(key)=\(shellQuote(profile.values[key] ?? ""))")
        }
    }
}
