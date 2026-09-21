import Foundation

extension RemoteAgentDeployer {
    final class PipeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }
        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    func attachReadability(_ pipe: Pipe, box: PipeBox) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            box.append(chunk)
        }
    }

    func collectPipe(_ pipe: Pipe, box: PipeBox) -> Data {
        pipe.fileHandleForReading.readabilityHandler = nil
        return box.value + pipe.fileHandleForReading.readDataToEndOfFile()
    }

    func decodeSSHLines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}
