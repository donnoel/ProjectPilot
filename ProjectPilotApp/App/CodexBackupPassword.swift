import Foundation
import Security

/// A local Keychain item, never an archive file, process argument, or UserDefault.
nonisolated enum CodexBackupPassword {
    private static let service = "com.donnoel.ProjectPilot.CodexBackup"
    private static let account = "disk-image-password-v1"

    static func validate(_ password: String, confirmation: String, recoverySaved: Bool) throws {
        guard password.count >= 16, password.utf8.count <= 512, !password.contains("\0"),
              !password.contains("\n"), !password.contains("\r") else {
            throw CodexCloudBackup.Failure("Use a backup password of at least 16 characters, without line breaks.")
        }
        guard password == confirmation else { throw CodexCloudBackup.Failure("The backup passwords do not match.") }
        guard recoverySaved else {
            throw CodexCloudBackup.Failure("Save this password somewhere you can access after losing this Mac.")
        }
    }

    static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let password = String(data: data, encoding: .utf8), !password.isEmpty else {
            throw CodexCloudBackup.Failure("The Codex backup password could not be read from Keychain. Unlock your login keychain and retry.")
        }
        return password
    }

    static func saveNew(_ password: String) throws {
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrLabel as String] = "ProjectPilot Codex backup password"
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CodexCloudBackup.Failure(status == errSecDuplicateItem
                ? "A backup password is already stored. It was not replaced."
                : "The backup password could not be saved in Keychain.")
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
