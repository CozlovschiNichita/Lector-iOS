import Foundation

struct TextSegment: Codable, Identifiable {
    let id: UUID
    var text: String
    let startTime: Double
    let endTime: Double

    init(text: String, startTime: Double, endTime: Double) {
        self.id = UUID()
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

struct LectureDTO: Codable, Identifiable {
    let id: UUID
    var title: String
    var fullText: String
    var summary: String?
    var summaryHistory: [String]?
    var folderID: UUID?
    let createdAt: Date?
    var localAudioPath: String?
    var status: String? // "processing", "completed", "error"
    var progress: Double? // 0.0 ... 1.0
    var segments: [TextSegment]?
    var temporaryAudioURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, fullText, summary, summaryHistory, folderID, createdAt, localAudioPath, status, progress, segments, temporaryAudioURL
    }
}

// Эта структура нужна для массовых операций (переименование, перемещение)
struct UpdateLecturesRequest: Codable {
    var lectureIDs: [UUID]
    var folderID: UUID?
    var newTitle: String?
    var fullText: String?      
    var segments: [TextSegment]?
    var summaryHistory: [String]?
}
