import SwiftUI
import SwiftData
import Combine

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager() // Одиночка (Singleton), доступен отовсюду
    
    @Published var networkMonitor = NetworkMonitor()
    
    private var isSyncing = false
    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Подписываемся на изменения интернета
        networkMonitor.$isConnected
            .dropFirst() // Игнорируем первый статус при запуске
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.triggerSync()
                }
            }
            .store(in: &cancellables)
        
        // проверяем базу каждые 15 с
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.triggerSync()
            }
        }
    }
    
    // Передаем контекст базы данных при старте приложения
    func setContext(_ context: ModelContext) {
        self.modelContext = context
        triggerSync() // Запускаем проверку сразу при входе
    }
    
    func triggerSync() {
        // Если нет интернета, уже идет загрузка или нет контекста — ничего не делаем
        guard networkMonitor.isConnected, !isSyncing, let context = modelContext else { return }
        
        // Ищем все лекции, которые ждут отправки
        let descriptor = FetchDescriptor<LocalLecture>(
            predicate: #Predicate<LocalLecture> { $0.status == "waiting_for_network" }
        )
        
        guard let pendingLectures = try? context.fetch(descriptor), !pendingLectures.isEmpty else { return }
        
        isSyncing = true
        
        Task {
            for lecture in pendingLectures {
                await uploadOfflineLecture(lecture, context: context)
            }
            isSyncing = false
        }
    }
    
    private func uploadOfflineLecture(_ initialLecture: LocalLecture, context: ModelContext) async {
        guard let fileName = initialLecture.localAudioPath else {
            initialLecture.status = "error"
            try? context.save()
            return
        }
        
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            initialLecture.status = "error"
            try? context.save()
            return
        }
        
        let lang = UserDefaults.standard.string(forKey: "aiLanguage") ?? "ru"
        let importService = ImportService() // Создаем локальный сервис конкретно для этого файла
        
        // Так как при старте загрузки сервер выдаст нам НОВЫЙ ID лекции,
        // нам нужно отслеживать активный ID, чтобы обновлять прогресс в базе
        var activeLectureID = initialLecture.id
        
        // Слушаем прогресс из ImportService и пишем его в SwiftData
        var cancellable: AnyCancellable?
        cancellable = importService.$uploadProgress
            .receive(on: RunLoop.main)
            .sink { progress in
                let desc = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == activeLectureID })
                if let active = try? context.fetch(desc).first {
                    active.progress = progress
                    try? context.save()
                }
            }
            
        do {
            // Ставим статус UI: Идет выгрузка
            let descStart = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == activeLectureID })
            if let active = try? context.fetch(descStart).first {
                active.status = "uploading"
                try? context.save()
            }
            
            // Начинаем заливку чанков
            let dto = try await importService.uploadFile(at: fileURL, language: lang) { startDTO in
                // Файл начал грузиться, сервер вернул настоящий ID
                // Мы удаляем старую временную офлайн-лекцию и создаем нормальную
                let newID = startDTO.id ?? UUID()
                let desc = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == activeLectureID })
                
                if let old = try? context.fetch(desc).first {
                    let oldTitle = old.title
                    let oldOwner = old.ownerID
                    let oldAudio = old.localAudioPath
                    
                    context.delete(old)
                    
                    let newL = LocalLecture(
                        id: newID,
                        title: old.title,
                        fullText: startDTO.fullText,
                        summary: old.summary,
                        folderID: old.folderID,         
                        audioPath: old.localAudioPath,
                        ownerID: old.ownerID,
                        status: "uploading",
                        progress: 0.0,
                        segmentsJSON: old.segmentsJSON,
                        isPinned: old.isPinned
                    )
                    newL.localAudioPath = oldAudio
                    context.insert(newL)
                    try? context.save()
                    
                    // Переключаем фокус трекера на новый ID
                    activeLectureID = newID
                }
            }
            
            // Завершение загрузки: ставим статус ожидания расшифровки
            let descFinal = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == activeLectureID })
            if let finalL = try? context.fetch(descFinal).first {
                finalL.status = "waiting_in_queue"
                finalL.progress = 0.0
                try? context.save()
            }
            
        } catch {
            print("Фоновая загрузка не удалась: \(error)")
            // Если сеть пропала во время выгрузки, возвращаем статус обратно
            let descFail = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == activeLectureID })
            if let failed = try? context.fetch(descFail).first {
                failed.status = "waiting_for_network"
                try? context.save()
            }
        }
        
        cancellable?.cancel()
    }
}
