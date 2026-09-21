import Foundation
import OSLog

extension ControllerStatusCache {
    public static func load(from url: URL = cacheURL) -> CachedControllerStatusPayload? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == CocoaError.fileReadNoSuchFile.rawValue {
                return nil
            }
            logger.error("Cache read failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(CachedControllerStatusPayload.self, from: data)
        } catch {
            logger.error("Cache decode failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                logger.error("Cache cleanup failed at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            return nil
        }
    }
}
