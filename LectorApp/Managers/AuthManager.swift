import Foundation
import Combine
import LocalAuthentication
import SwiftData

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var isUnlocked: Bool = false
    
    init() {
        self.isAuthenticated = KeychainManager.shared.getRefreshToken() != nil
        
        let timeout = UserDefaults.standard.double(forKey: "biometricTimeout")
        
        if timeout < 0 {
            self.isUnlocked = true
        } else {
            // Если мы выкинули приложение из ОЗУ, дата всё равно сохранилась на диске
            if let bgDate = UserDefaults.standard.object(forKey: "lastExitDate") as? Date {
                let timeAway = Date().timeIntervalSince(bgDate)
                self.isUnlocked = timeAway < timeout
            } else {
                self.isUnlocked = false
            }
        }
    }
    
    func getCurrentUserID() -> String? {
        return UserDefaults.standard.string(forKey: "current_user_id")
    }
    
    func logout() {
        KeychainManager.shared.deleteTokens()
        UserDefaults.standard.removeObject(forKey: "current_user_id")
        
        NotificationCenter.default.post(name: NSNotification.Name("UserDidLogout"), object: nil)
        
        isAuthenticated = false
        isUnlocked = false
    }
    
    func login(tokens: TokenResponse) {
        KeychainManager.shared.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
        isAuthenticated = true
        isUnlocked = true
    }
    
    func authenticateWithBiometrics() {
        let timeout = UserDefaults.standard.double(forKey: "biometricTimeout")
        
        if timeout < 0 {
            self.isUnlocked = true
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Разблокируйте Lector для доступа к записям"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, authError in
                DispatchQueue.main.async {
                    if success {
                        self.isUnlocked = true
                        UserDefaults.standard.removeObject(forKey: "lastExitDate")
                    } else {
                        print("Биометрия не пройдена: \(authError?.localizedDescription ?? "")")
                    }
                }
            }
        } else {
            self.isUnlocked = true
        }
    }
    
    // MARK: - Очистка всех локальных данных
    func wipeAllLocalData(modelContext: ModelContext) {
        // Очищаем SwiftData
        do {
            try modelContext.delete(model: LocalLecture.self)
            try modelContext.delete(model: LocalFolder.self)
            try modelContext.save()
        } catch {
            print("Ошибка при удалении данных SwiftData: \(error)")
        }
        
        // Очищаем файловую систему (все аудиофайлы)
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
                for fileURL in fileURLs {
                    try fileManager.removeItem(at: fileURL)
                }
            } catch {
                print("Ошибка при очистке файлов: \(error)")
            }
        }
    }
}
