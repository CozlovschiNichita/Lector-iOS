import Foundation

class FolderService {
    
    func fetchFolders() async throws -> [FolderDTO] {
        let (data, _) = try await apiRequest(path: "/folders", method: "GET")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FolderDTO].self, from: data)
    }

    func createFolder(name: String, colorHex: String?) async throws -> FolderDTO {
        var body: [String: Any] = ["name": name]
        if let colorHex = colorHex {
            body["colorHex"] = colorHex
        }
        let (data, _) = try await apiRequest(path: "/folders", method: "POST", body: body)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FolderDTO.self, from: data)
    }

    func updateLecturesBatch(ids: [UUID], folderID: UUID? = nil, newTitle: String? = nil) async throws {
        let request = UpdateLecturesRequest(lectureIDs: ids, folderID: folderID, newTitle: newTitle)
        _ = try await apiRequest(path: "/lectures/batch", method: "PATCH", body: request)
    }
    
    func deleteFolder(id: UUID) async throws {
        _ = try await apiRequest(path: "/folders/\(id.uuidString)", method: "DELETE")
    }
    
    func updateFolder(id: UUID, name: String, colorHex: String?) async throws {
        var body: [String: Any] = ["name": name]
        if let colorHex = colorHex {
            body["colorHex"] = colorHex
        }
        _ = try await apiRequest(path: "/folders/\(id.uuidString)", method: "PATCH", body: body)
    }
    
    // MARK: - Универсальный запрос через APIClient
    private func apiRequest(path: String, method: String, body: Any? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://api.vtuza.us" + path) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if let token = KeychainManager.shared.getAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let encodeableBody = body as? UpdateLecturesRequest {
                request.httpBody = try? JSONEncoder().encode(encodeableBody)
            } else if let dictBody = body as? [String: Any] {
                request.httpBody = try? JSONSerialization.data(withJSONObject: dictBody)
            }
        }
        
        return try await APIClient.shared.request(request)
    }
}
