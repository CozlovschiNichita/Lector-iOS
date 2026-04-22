import Foundation

// Модель для папки
struct FolderDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date?
    var colorHex: String?
}
