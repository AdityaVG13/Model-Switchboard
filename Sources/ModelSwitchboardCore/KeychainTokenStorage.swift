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
        // Prefer the non-group item first. Ad-hoc / local re-signs of the menu bar
        // app cannot always read App Group keychain items, and a failed group
        // probe used to surface as "token missing" so users re-pasted forever.
        if let value = load(accessGroup: nil), !value.isEmpty {
            return value
        }
        if let accessGroup, let value = load(accessGroup: accessGroup), !value.isEmpty {
            // Heal: mirror into the durable non-group slot so the next launch
            // (and ad-hoc rebuilds) keep working without a keychain prompt.
            _ = save(data: Data(value.utf8), accessGroup: nil)
            return value
        }
        return nil
    }

    public func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete()
            return
        }
        let data = Data(trimmed.utf8)
        // Always write the non-group item - this is what survives rebuilds of
        // ad-hoc signed debug installs without re-authorizing keychain access.
        _ = save(data: data, accessGroup: nil)
        // Best-effort App Group copy for the widget / shared suite.
        if let accessGroup {
            _ = save(data: data, accessGroup: accessGroup)
        }
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
        // Update-first: avoids duplicate-item races and keeps the existing
        // keychain ACL so the user is not prompted again on every save.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery(accessGroup: accessGroup) as CFDictionary,
            update as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }
        if updateStatus != errSecItemNotFound {
            // Fall through to add only when the item is missing; other errors
            // (auth failed, etc.) still try add after a delete.
            _ = delete(accessGroup: accessGroup)
        }
        var query = baseQuery(accessGroup: accessGroup)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil)
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
