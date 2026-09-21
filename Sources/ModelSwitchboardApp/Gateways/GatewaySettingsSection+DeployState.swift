import Foundation

extension GatewaySettingsSection {
    enum DeployState: Equatable {
        case idle
        case running
        case success(String)
        case failure(String)
    }
}
