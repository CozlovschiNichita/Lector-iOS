import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private let accessTag = "com.lector.accessToken"
    private let refreshTag = "com.lector.refreshToken"
    
    // Сохранение пары токенов
    func saveTokens(access: String, refresh: String) {
        save(key: accessTag, data: access)
        save(key: refreshTag, data: refresh)
    }
    
    func getAccessToken() -> String? {
        return load(key: accessTag)
    }
    
    func getRefreshToken() -> String? {
        return load(key: refreshTag)
    }
    
    func deleteTokens() {
        delete(key: accessTag)
        delete(key: refreshTag)
    }
    
    // MARK: - Private Helpers
    private func save(key: String, data: String) {
        let data = Data(data.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
