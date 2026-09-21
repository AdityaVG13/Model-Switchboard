import Foundation
import Security

extension KeychainTokenStorage {
    func save(data: Data, accessGroup: String?) -> OSStatus {
        // Update-first: avoids duplicate-item races and keeps the existing
        // keychain ACL so the user is not prompted again on every save.
        let updateStatus = SecItemUpdate(
            baseQuery(accessGroup: accessGroup) as CFDictionary,
            saveAttributes(data: data) as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }
        return addAfterUpdateMiss(data: data, accessGroup: accessGroup, updateStatus: updateStatus)
    }

    func saveAttributes(data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }

    func addAfterUpdateMiss(
        data: Data,
        accessGroup: String?,
        updateStatus: OSStatus
    ) -> OSStatus {
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
}
