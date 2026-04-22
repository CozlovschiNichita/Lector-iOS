import Foundation
import SwiftData

// MARK: - Модель Папки
@Model
final class LocalFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var ownerID: String
    var isSynced: Bool
    var colorHex: String?
    
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        ownerID: String,
        isSynced: Bool = false,
        colorHex: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.ownerID = ownerID
        self.isSynced = isSynced
        self.colorHex = colorHex
        self.isPinned = isPinned
    }
}

// MARK: - Модель Лекции
@Model
final class LocalLecture {
    @Attribute(.unique) var id: UUID
    var title: String
    var fullText: String
    var summary: String?
    var summaryHistoryJSON: String?
    var createdAt: Date
    var localAudioPath: String?
    var ownerID: String
    var folderID: UUID?
    var status: String?
    var progress: Double?
    var segmentsJSON: String?
    var isPinned: Bool

    init(
        id: UUID,
        title: String,
        fullText: String,
        summary: String? = nil,
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        audioPath: String? = nil,
        ownerID: String,
        status: String? = "completed",
        progress: Double? = 1.0,
        segmentsJSON: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.fullText = fullText
        self.summary = summary
        self.folderID = folderID
        self.createdAt = createdAt
        self.localAudioPath = audioPath
        self.ownerID = ownerID
        self.status = status
        self.progress = progress
        self.segmentsJSON = segmentsJSON
        self.isPinned = isPinned
    }

    // Вспомогательный метод для парсинга сегментов из JSON
    func getSegments() -> [TextSegment] {
        guard let json = segmentsJSON else { return [] }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([TextSegment].self, from: json.data(using: .utf8) ?? Data())
        } catch {
            return []
        }
    }
    
    // Вспомогательный метод для получения истории конспектов
    func getSummaryHistory() -> [String] {
        guard let json = summaryHistoryJSON,
              let data = json.data(using: .utf8) else { return [] }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([String].self, from: data)
        } catch {
            return []
        }
    }
}
