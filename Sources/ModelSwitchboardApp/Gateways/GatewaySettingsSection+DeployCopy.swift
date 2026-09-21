import Foundation
import ModelSwitchboardCore

extension GatewaySettingsSection {
    func deploySuccessSuffix(pairingLink: String?) -> String {
        pairingLink == nil
            ? "" : " The host printed its pairing code, so the connection details check out."
    }

    func tailscaleTokenHint(authToken: String?) -> String {
        (authToken?.isEmpty == false)
            ? " Bearer token captured into the form."
            : " Paste the bearer token from the host if auth is enabled."
    }
}
