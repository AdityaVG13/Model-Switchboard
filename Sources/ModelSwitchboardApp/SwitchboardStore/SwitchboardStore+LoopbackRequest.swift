import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    nonisolated static func isLoopbackConnectionRefused(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == ECONNREFUSED {
            return true
        }
        return false
    }

    nonisolated static func loopbackProbeRequest(for status: ModelProfileStatus) -> URLRequest? {
        guard let baseURL = URL(string: status.baseURL) else { return nil }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Constants.loopbackEndpointProbeTimeoutSeconds
        return request
    }
}
