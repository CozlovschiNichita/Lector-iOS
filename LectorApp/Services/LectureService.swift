import Foundation

class LectureService {
    private let baseURL = "https://api.vtuza.us/api/lectures"
    
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    func fetchLectures() async throws -> [LectureDTO] {
        guard let url = URL(string: baseURL) else { return [] }
        var request = URLRequest(url: url)
        
        let (data, _) = try await APIClient.shared.request(request)
        return try decoder.decode([LectureDTO].self, from: data)
    }
    
    // MARK: Метод для получения одной лекции (нужен для поллинга)
    func getLecture(id: UUID) async throws -> LectureDTO {
        let url = URL(string: "\(baseURL)/\(id.uuidString)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // APIClient.shared.request сам подставит токен
        let (data, _) = try await APIClient.shared.request(request)
        return try decoder.decode(LectureDTO.self, from: data)
    }
    
    func summarize(lectureID: UUID, language: String) async throws -> LectureDTO {
        let url = URL(string: "\(baseURL)/\(lectureID)/summarize?lang=\(language)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, _) = try await APIClient.shared.request(request)
        return try decoder.decode(LectureDTO.self, from: data)
    }
    
    func deleteLecture(id: UUID) async throws {
        let url = URL(string: "\(baseURL)/\(id.uuidString)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        _ = try await APIClient.shared.request(request)
    }

    func updateLecture(id: UUID, newTitle: String? = nil, folderID: UUID? = nil, fullText: String? = nil, segments: [TextSegment]? = nil, summaryHistory: [String]? = nil) async throws {
        guard let url = URL(string: "\(baseURL)/batch") else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = UpdateLecturesRequest(
            lectureIDs: [id],
            folderID: folderID,
            newTitle: newTitle,
            fullText: fullText,
            segments: segments,
            summaryHistory: summaryHistory
        )
        request.httpBody = try JSONEncoder().encode(payload)
        
        _ = try await APIClient.shared.request(request)
    }
}
