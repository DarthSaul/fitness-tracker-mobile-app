import Foundation
import OSLog

// MARK: - Errors
enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedData

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Keychain item not found."
        case .saveFailed(let s): return "Keychain save failed: \(s)."
        case .loadFailed(let s): return "Keychain load failed: \(s)."
        case .deleteFailed(let s): return "Keychain delete failed: \(s)."
        case .unexpectedData: return "Unexpected data format in Keychain."
        }
    }
}

// MARK: - Service
actor KeychainService {
    private let service = "me.fitness-app.tracker"

    // MARK: - Save
    func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.unexpectedData }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)

        var attrs = query
        attrs[kSecValueData] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
        Logger.auth.debug("Keychain: saved key \(key.rawValue, privacy: .private)")
    }

    // MARK: - Load
    func load(_ key: KeychainKey) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.itemNotFound : KeychainError.loadFailed(status)
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }

    // MARK: - Delete
    func delete(_ key: KeychainKey) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
        Logger.auth.debug("Keychain: deleted key \(key.rawValue, privacy: .private)")
    }
}
