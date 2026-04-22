import Foundation
import Combine
import SwiftUI
import GoogleSignIn

@MainActor
class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var password = "" 
    
    @Published var errorMessage = ""
    @Published var isLoading = false
    
    private let authService = AuthService()
    
    // MARK: - Валидация
    var hasMinLength: Bool { password.count >= 6 }
    var hasUppercase: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    var hasDigit: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    
    var isPasswordValid: Bool {
        hasMinLength && hasUppercase && hasDigit
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailFormat = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailFormat)
        return emailPredicate.evaluate(with: email)
    }
    
    // MARK: - Вход
    func login() async {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Заполните все поля"
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Введите корректный email адрес"
            return
        }
        
        isLoading = true; errorMessage = ""
        do {
            let tokens = try await authService.login(email: email.lowercased(), password: password)
            handleSuccessfulAuth(tokens: tokens)
        } catch AuthError.serverError(let msg) {
            errorMessage = msg
        } catch { errorMessage = "Неверный email или пароль" }
        isLoading = false
    }
    
    // MARK: - Регистрация
    func register() async {
        guard !email.isEmpty && !password.isEmpty && !firstName.isEmpty else {
            errorMessage = "Заполните все обязательные поля"
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Введите корректный email адрес"
            return
        }
        guard isPasswordValid else {
            errorMessage = "Пароль не соответствует требованиям безопасности"
            return
        }
        
        isLoading = true; errorMessage = ""
        do {
            let tokens = try await authService.register(email: email.lowercased(), password: password, firstName: firstName, lastName: lastName)
            handleSuccessfulAuth(tokens: tokens)
        } catch AuthError.serverError(let msg) {
            errorMessage = msg
        } catch { errorMessage = "Ошибка регистрации. Проверьте подключение." }
        isLoading = false
    }
    
    // MARK: - Вход через Google
    func signInWithGoogle() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else {
            errorMessage = "Внутренняя ошибка интерфейса"
            return
        }
        
        isLoading = true; errorMessage = ""
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google не предоставил токен"
                isLoading = false; return
            }
            let tokens = try await authService.googleLogin(idToken: idToken)
            handleSuccessfulAuth(tokens: tokens)
        } catch {
            print("Google Sign In Error: \(error.localizedDescription)")
        }
        isLoading = false
    }
    
    // MARK: - Обработка успеха
    private func handleSuccessfulAuth(tokens: TokenResponse) {
        if let userID = extractUserID(from: tokens.accessToken) {
            UserDefaults.standard.set(userID, forKey: "current_user_id")
        }
        AuthManager.shared.login(tokens: tokens)
    }
    
    private func extractUserID(from token: String) -> String? {
        let segments = token.components(separatedBy: ".")
        guard segments.count > 1 else { return nil }
        var base64String = segments[1]
        base64String = base64String.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64String.count % 4 != 0 { base64String.append("=") }
        guard let payloadData = Data(base64Encoded: base64String),
              let json = try? JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any],
              let subject = json["sub"] as? String else { return nil }
        return subject
    }
}
