import Foundation

extension SSHTunnelManager {
    func makeTunnelProcess() -> Process {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = tunnelArguments()
        SSHInvocation.applyEnvironment(to: process)
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        return process
    }

    func attachStderr(_ process: Process) {
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { await self.appendStderr(text) }
        }
    }

    func reallocateLocalPortIfTaken(force: Bool = false) async {
        if !force, Self.isLoopbackPortFree(localPort) { return }
        let newPort = Self.allocateLoopbackPort()
        guard newPort != 0, newPort != localPort else { return }
        localPort = newPort
        await onLocalPortChange(instanceID, newPort)
    }
}
