import Foundation
import Security

public final class KeychainTokenStorage: Sendable {
    public static let shared = KeychainTokenStorage(
        service: "io.modelswitchboard.controller-auth-token",
        accessGroup: "group.io.modelswitchboard.shared"
    )

    public static let legacyAccount = "controllerAuthToken"

    private let service: String
    private let accessGroup: String?
    private let account: String

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

    public func load() -> String? {
        if let accessGroup, let value = load(accessGroup: accessGroup) {
            return value
        }
        return load(accessGroup: nil)
    }

    public func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return
        }
        let data = Data(trimmed.utf8)
        if let accessGroup, save(data: data, accessGroup: accessGroup) == errSecSuccess {
            return
        }
        _ = save(data: data, accessGroup: nil)
    }

    public func delete() {
        if let accessGroup {
            _ = delete(accessGroup: accessGroup)
        }
        _ = delete(accessGroup: nil)
    }

    private func load(accessGroup: String?) -> String? {
        var query = baseQuery(accessGroup: accessGroup)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func save(data: Data, accessGroup: String?) -> OSStatus {
        var query = baseQuery(accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecDuplicateItem else { return status }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemUpdate(
            baseQuery(accessGroup: accessGroup) as CFDictionary,
            update as CFDictionary
        )
    }

    private func delete(accessGroup: String?) -> OSStatus {
        SecItemDelete(baseQuery(accessGroup: accessGroup) as CFDictionary)
    }

    private func baseQuery(accessGroup: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
