import Foundation

class APIClient {
    static let shared = APIClient()
    private let authService = AuthService() // Используем для обновления токена
    private var refreshTask: Task<String, Error>?
    
    private init() {}
    
    // Универсальный метод для отправки HTTP запросов
    func request(_ request: URLRequest, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        var req = request
        
        // Всегда подставляем актуальный Access Token
        if let token = KeychainManager.shared.getAccessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // первый запрос
        let (data, response) = try await session.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Если сервер сказал "Токен просрочен" (401 Unauthorized)
        if httpResponse.statusCode == 401 {
            print("--- [APIClient] Токен истек, пытаемся обновить... ---")
            
            let newToken = try await refreshToken()  // авто-рефреш
            
            req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
            
            // запрос с новым токеном
            let (retryData, retryResponse) = try await session.data(for: req)
            guard let retryHttpResponse = retryResponse as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            // Если после обновления токена получаем 401 - значит Refresh токен тоже умер
            if retryHttpResponse.statusCode == 401 {
                await logoutUser()
                throw URLError(.userAuthenticationRequired)
            }
            
            return (retryData, retryHttpResponse)
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - ПРОВЕРКА ТОКЕНА ДЛЯ СОКЕТОВ
    func ensureValidToken() async throws -> String {
        guard let token = KeychainManager.shared.getAccessToken() else {
            await logoutUser()
            throw URLError(.userAuthenticationRequired)
        }
        
        if isTokenExpired(token) {
            print("--- [APIClient] Токен истек (или истекает), обновляем перед открытием сокета... ---")
            return try await refreshToken()
        }
        
        return token
    }
    
    /// Локально расшифровывает JWT и проверяет поле exp (с запасом в 60 секунд)
    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return true }
        
        var base64 = parts[1]
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return true }
        
        let expDate = Date(timeIntervalSince1970: exp)
        
        return Date() >= expDate.addingTimeInterval(-60)
    }
    
    // MARK: - Логика обновления токена
    private func refreshToken() async throws -> String {
        if let task = refreshTask {
            return try await task.value
        }
        
        let task = Task<String, Error> {
            guard let refreshToken = KeychainManager.shared.getRefreshToken() else {
                await logoutUser()
                throw URLError(.userAuthenticationRequired)
            }
            
            do {
                let tokens = try await authService.refresh(refreshToken: refreshToken)
                KeychainManager.shared.saveTokens(access: tokens.accessToken, refresh: tokens.refreshToken)
                return tokens.accessToken
            } catch {
                await logoutUser()
                throw URLError(.userAuthenticationRequired)
            }
        }
        
        self.refreshTask = task
        let newToken = try await task.value
        self.refreshTask = nil // Очищаем после успешного обновления
        
        return newToken
    }
    
    @MainActor
    private func logoutUser() async {
        AuthManager.shared.logout()
    }
}
