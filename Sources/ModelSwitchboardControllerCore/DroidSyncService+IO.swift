import Foundation

extension DroidSyncService {
    func readObject(_ url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ControllerError.operationFailed(
                "\(url.lastPathComponent) must be a JSON object; refusing to overwrite it.")
        }
        return object
    }

    func write(_ object: [String: Any], to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = try JSONSupport.data(object)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
