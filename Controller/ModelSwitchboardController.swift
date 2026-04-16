import Dispatch
import Foundation

struct Config {
    let root: URL
    let host: String
    let port: String
}

enum LauncherError: Error {
    case missingValue(String)
}

func parseConfig(arguments: [String]) throws -> Config {
    var rootPath: String?
    var host = "127.0.0.1"
    var port = "8877"

    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--root":
            guard let value = iterator.next() else { throw LauncherError.missingValue("--root") }
            rootPath = value
        case "--host":
            guard let value = iterator.next() else { throw LauncherError.missingValue("--host") }
            host = value
        case "--port":
            guard let value = iterator.next() else { throw LauncherError.missingValue("--port") }
            port = value
        default:
            continue
        }
    }

    let resolvedRoot = URL(fileURLWithPath: rootPath ?? FileManager.default.currentDirectoryPath)
    return Config(root: resolvedRoot, host: host, port: port)
}

let config = try parseConfig(arguments: Array(CommandLine.arguments.dropFirst()))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
process.arguments = [
    config.root.appendingPathComponent("modelctl.py").path,
    "serve-web",
    "--host", config.host,
    "--port", config.port,
]
process.currentDirectoryURL = config.root
process.standardOutput = FileHandle.standardOutput
process.standardError = FileHandle.standardError

signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)

let signalQueue = DispatchQueue(label: "io.modelswitchboard.controller.signals")
let signalForwarder: (Int32) -> DispatchSourceSignal = { signalNumber in
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: signalQueue)
    source.setEventHandler {
        if process.isRunning {
            process.terminate()
        } else {
            exit(0)
        }
    }
    source.resume()
    return source
}

let signalSources = [signalForwarder(SIGINT), signalForwarder(SIGTERM)]
_ = signalSources

process.terminationHandler = { child in
    exit(child.terminationStatus)
}

try process.run()
dispatchMain()
