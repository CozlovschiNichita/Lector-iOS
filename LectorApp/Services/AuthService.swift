import Foundation

enum AuthError: Error {
    case invalidResponse
    case serverError(String)
    case decodingError
    case networkError
}

// DTO для ответа сервера
struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
}

class AuthService {
    private let baseURL = "https://api.vtuza.us/auth"
    
    // MARK: - Регистрация
    func register(email: String, password: String, firstName: String, lastName: String) async throws -> TokenResponse {
        guard let url = URL(string: "\(baseURL)/register") else { throw AuthError.invalidResponse }
        
        let body = ["email": email, "password": password, "firstName": firstName, "lastName": lastName]
        return try await makeAuthRequest(url: url, body: body)
    }
    
    // MARK: - Логин по паролю
    func login(email: String, password: String) async throws -> TokenResponse {
        guard let url = URL(string: "\(baseURL)/login") else { throw AuthError.invalidResponse }
        
        let body = ["email": email, "password": password]
        return try await makeAuthRequest(url: url, body: body)
    }
    
    // MARK: - Обновление токена (Refresh)
    func refresh(refreshToken: String) async throws -> TokenResponse {
        guard let url = URL(string: "\(baseURL)/refresh") else { throw AuthError.invalidResponse }
        
        let body = ["refreshToken": refreshToken]
        return try await makeAuthRequest(url: url, body: body)
    }
    
    // MARK: - Вход через Google
    func googleLogin(idToken: String) async throws -> TokenResponse {
        guard let url = URL(string: "\(baseURL)/google-login") else { throw AuthError.invalidResponse }
        
        let body = ["idToken": idToken]
        return try await makeAuthRequest(url: url, body: body)
    }
    
    // MARK: - Универсальный метод запроса (Без токена)
    private func makeAuthRequest(url: URL, body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                do {
                    return try JSONDecoder().decode(TokenResponse.self, from: data)
                } catch {
                    throw AuthError.decodingError
                }
            } else {
                struct ServerError: Codable { let reason: String }
                if let errorObj = try? JSONDecoder().decode(ServerError.self, from: data) {
                    throw AuthError.serverError(errorObj.reason)
                } else {
                    throw AuthError.serverError("Ошибка сервера: \(httpResponse.statusCode)")
                }
            }
        } catch let authError as AuthError {
            throw authError
        } catch {
            throw AuthError.serverError("Нет связи с сервером")
        }
    }
    
    // MARK: - Восстановление пароля
    func forgotPassword(email: String) async throws {
        guard let url = URL(string: "\(baseURL)/forgot-password") else { throw AuthError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["email": email])
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.serverError("Не удалось отправить письмо")
        }
    }
    
    func resetPassword(email: String, code: String, newPassword: String) async throws {
        guard let url = URL(string: "\(baseURL)/reset-password") else { throw AuthError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["email": email, "code": code, "newPassword": newPassword]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
        
        if httpResponse.statusCode != 200 {
            struct ServerError: Codable { let reason: String }
            if let errorObj = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw AuthError.serverError(errorObj.reason)
            }
            throw AuthError.serverError("Неверный код или ошибка сервера")
        }
    }

    // MARK: - Удаление аккаунта
    func deleteAccount() async throws {
        guard let url = URL(string: "\(baseURL)/account") else { throw AuthError.invalidResponse }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        do {
            let (data, response) = try await APIClient.shared.request(request)
            guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.invalidResponse }
            
            if httpResponse.statusCode != 204 && httpResponse.statusCode != 200 {
                struct ServerError: Codable { let reason: String }
                if let errorObj = try? JSONDecoder().decode(ServerError.self, from: data) {
                    throw AuthError.serverError(errorObj.reason)
                }
                throw AuthError.serverError("Не удалось удалить аккаунт.")
            }
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            throw AuthError.serverError("Сессия истекла. Пожалуйста, авторизуйтесь заново.")
        } catch {
            throw AuthError.serverError("Ошибка сети при удалении аккаунта.")
        }
    }
}
