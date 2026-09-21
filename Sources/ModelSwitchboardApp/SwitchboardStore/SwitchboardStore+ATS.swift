import Foundation
import ModelSwitchboardCore

extension SwitchboardStore {
    /// ATS is app-target-only (rebuild / tunnel remediation). Other transport
    /// copy lives in `UserFacingControllerError` so the widget shares it.
    nonisolated static func mapATSError(_ error: Error) -> String? {
        let chain = UserFacingControllerError.nsErrorChain(error)
        // NSURLErrorAppTransportSecurityRequiresSecureConnection == -1022
        // NSURLErrorSecureConnectionFailed == -1200
        let isATS = chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1022
        } || chain.contains {
            $0.domain == NSURLErrorDomain && $0.code == -1200
        }
        if isATS {
            return "Blocked plain HTTP to this gateway (App Transport Security). Rebuild the app with ATS exceptions, or switch the gateway to SSH tunnel."
        }
        return nil
    }
}
