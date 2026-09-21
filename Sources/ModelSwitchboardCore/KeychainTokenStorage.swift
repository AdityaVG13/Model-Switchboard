import Foundation
import Security

public final class KeychainTokenStorage: Sendable {
    public static let shared = KeychainTokenStorage(
        service: "io.modelswitchboard.controller-auth-token",
        accessGroup: "group.io.modelswitchboard.shared"
    )

    public static let legacyAccount = "controllerAuthToken"

    let service: String
    let accessGroup: String?
    let account: String

    public init(service: String, accessGroup: String? = nil, account: String = KeychainTokenStorage.legacyAccount) {
        self.service = service
        self.accessGroup = accessGroup
        self.account = account
    }

    /// Storage for a remote gateway's bearer token, isolated per gateway id.
    public static func forGateway(id: String) -> KeychainTokenStorage {
        KeychainTokenStorage(
            service: "io.modelswitchboard.controller-auth-token",
            accessGroup: "group.io.modelswitchboard.shared",
            account: "gateway-\(id)"
        )
    }
}
