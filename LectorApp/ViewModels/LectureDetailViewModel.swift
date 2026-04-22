import SwiftUI
import SwiftData
import AVFoundation
import Combine

@MainActor
class LectureDetailViewModel: ObservableObject {
    @Published var lecture: LectureDTO {
        didSet {
            // Вычисляем заново ТОЛЬКО если лекция реально обновилась
            updateDerivedState()
        }
    }
    
    // Кэшированные состояния для UI, чтобы разгрузить главный поток
    @Published var hasLocalAudio: Bool = false
    @Published var isRealTextEmpty: Bool = true
    
    @Published var isGeneratingSummary = false
    @Published var errorMessage: String?
    
    // Плеер и UI
    @Published var showCopyToast = false
    
    // Конвертер
    @Published var converter = AudioConverterService()
    
    // Редактирование текста
    @Published var isEditingText = false
    @Published var editedFullText = ""
    
    // Состояние загрузки аудио с сервера
    @Published var isDownloadingAudio = false
    
    @Published var searchText: String = "" {
        didSet {
            updateHighlightedSegments()
        }
    }
    
    // Храним уже готовые (отформатированные) строки для каждого сегмента
    @Published var highlightedSegments: [UUID: AttributedString] = [:]
    
    private let service = LectureService()
    private var pollingTimer: Timer?
    private var pollingCount = 0
    
    init(lecture: LectureDTO) {
        self.lecture = lecture
        updateDerivedState()
    }
    
    // Предварительный расчет тяжелых свойств, чтобы View не делала это 60 раз в секунду
    private func updateDerivedState() {
        let text = lecture.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        isRealTextEmpty = text.isEmpty || text.contains("Ожидает расшифровки")
        
        if let path = lecture.localAudioPath, !path.isEmpty {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path)
            hasLocalAudio = FileManager.default.fileExists(atPath: url.path)
        } else {
            hasLocalAudio = false
        }
        updateHighlightedSegments()
    }
    
    private func updateHighlightedSegments() {
        guard let segments = lecture.segments else { return }
        
        var newCache: [UUID: AttributedString] = [:]
        let cleanSearch = searchText.trimmingCharacters(in: .whitespaces)
        
        for segment in segments {
            var attrStr = AttributedString(segment.text)
            
            if !cleanSearch.isEmpty {
                var searchRange = attrStr.startIndex..<attrStr.endIndex
                while let range = attrStr[searchRange].range(of: cleanSearch, options: .caseInsensitive) {
                    attrStr[range].backgroundColor = .yellow.opacity(0.8)
                    attrStr[range].foregroundColor = .black
                    searchRange = range.upperBound..<attrStr.endIndex
                }
            }
            newCache[segment.id] = attrStr
        }
        
        self.highlightedSegments = newCache
    }
    
    // MARK: - Редактирование текста
    func startEditing() {
        editedFullText = lecture.fullText
        isEditingText = true
    }
    
    func saveEditedText(context: ModelContext) {
        lecture.fullText = editedFullText
        isEditingText = false
        
        updateLocalLecture(lecture, context: context)
        
        Task {
            try? await service.updateLecture(id: lecture.id, fullText: editedFullText)
        }
    }
    
    func cancelEditing() {
        isEditingText = false
    }
    
    func deleteSummary(at index: Int, context: ModelContext) {
        guard var history = lecture.summaryHistory, history.indices.contains(index) else { return }
        
        withAnimation {
            history.remove(at: index)
            lecture.summaryHistory = history
            lecture.summary = history.last
        }
        
        updateLocalLecture(lecture, context: context)
        
        Task {
            try? await service.updateLecture(id: lecture.id, summaryHistory: history)
        }
    }
    
    func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation {
            showCopyToast = true
        }
    }
    
    // MARK: - Экспорт и Файлы
    func exportDocument(format: ExportFormat, translatedFullText: String? = nil, presentAction: @escaping (URL) -> Void) {
        guard !lecture.fullText.isEmpty else {
            self.errorMessage = "Текст пуст"
            return
        }
        
        let url: URL?
        switch format {
        case .pdf:
            url = ExportManager.shared.generatePDF(from: lecture, translatedFullText: translatedFullText)
        case .rtf:
            url = ExportManager.shared.generateRTF(from: lecture, translatedFullText: translatedFullText)
        case .txt:
            url = ExportManager.shared.generateTXT(from: lecture, translatedFullText: translatedFullText)
        case .srt:
            if let segments = lecture.segments {
                url = ExportManager.shared.generateSRT(from: segments, title: lecture.title)
            } else { url = nil }
        }
        
        if let finalURL = url {
            presentAction(finalURL)
        } else {
            self.errorMessage = "Ошибка экспорта"
        }
    }
    
    func shareAudio(as format: AudioFormat, presentAction: @escaping (URL) -> Void) {
        guard let fileName = lecture.localAudioPath else { return }
        let url = getFileURL(fileName: fileName)
        
        if url.pathExtension.lowercased() == format.extensionName {
            presentAction(url)
        } else {
            converter.convert(sourceURL: url, to: format) { tempURL in
                if let tempURL = tempURL { presentAction(tempURL) }
            }
        }
    }
    
    func handleManualConversion(to format: AudioFormat, context: ModelContext) {
        guard let fileName = lecture.localAudioPath else { return }
        let sourceURL = getFileURL(fileName: fileName)
        GlobalAudioPlayer.shared.stop()
        
        converter.convert(sourceURL: sourceURL, to: format) { newURL in
            guard let newURL = newURL else { return }
            try? FileManager.default.removeItem(at: sourceURL)
            let newFileName = newURL.lastPathComponent
            withAnimation { self.lecture.localAudioPath = newFileName }
            self.updateDatabasePath(newPath: newFileName, context: context)
        }
    }
    
    func deleteAudioFile(context: ModelContext) {
        guard let fileName = lecture.localAudioPath else { return }
        let url = getFileURL(fileName: fileName)
        GlobalAudioPlayer.shared.stop()
        try? FileManager.default.removeItem(at: url)
        withAnimation { self.lecture.localAudioPath = nil }
        updateDatabasePath(newPath: "", context: context)
    }
    
    // MARK: - Взаимодействие с сервером
    func generateSummary(language: String = "ru", context: ModelContext) {
        errorMessage = nil
        withAnimation {
            isGeneratingSummary = true
        }
        
        Task {
            do {
                print("--- [ИИ] Отправляем запрос на генерацию конспекта (язык: \(language)) ---")
                
                let updated = try await service.summarize(lectureID: lecture.id, language: language)
                
                print("--- [ИИ] Успешный ответ от сервера получен ---")
                
                var merged = updated
                merged.localAudioPath = self.lecture.localAudioPath
                
                withAnimation(.spring()) {
                    self.lecture = merged
                    // Сразу сохраняем изменения в локальную БД
                    self.updateLocalLecture(merged, context: context)
                    
                    if merged.status == "completed" || merged.status == "ready" || merged.status == "error" {
                        self.isGeneratingSummary = false
                    }
                }
                
                self.startPolling(context: context)
                
            } catch {
                print("!!! [ИИ] ОШИБКА ГЕНЕРАЦИИ КОНСПЕКТА !!!")
                print("Детали ошибки: \(error)")
                
                self.errorMessage = "Ошибка сети/сервера (см. логи)"
                withAnimation { self.isGeneratingSummary = false }
            }
        }
    }
    
    func startPolling(context: ModelContext) {
        cleanUp()
        pollingCount = 0
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.pollingCount += 1
            Task { @MainActor in
                await self.syncThisLecture(context: context)
            }
            if self.pollingCount >= 120 { self.cleanUp() }
        }
    }
    
    // MARK: - ИДЕМПОТЕНТНАЯ СИНХРОНИЗАЦИЯ (Защита от мерцания UI)
    func syncThisLecture(context: ModelContext) async {
        do {
            let updatedLecture = try await service.getLecture(id: lecture.id)
            
            let statusChanged = self.lecture.status != updatedLecture.status
            let progressChanged = abs((self.lecture.progress ?? 0) - (updatedLecture.progress ?? 0)) > 0.001
            let textChanged = self.lecture.fullText != updatedLecture.fullText
            let summaryChanged = self.lecture.summary != updatedLecture.summary
            let summaryCountChanged = (self.lecture.summaryHistory?.count ?? 0) != (updatedLecture.summaryHistory?.count ?? 0)
            let segmentsCountChanged = (self.lecture.segments?.count ?? 0) != (updatedLecture.segments?.count ?? 0)
            
            let hasMeaningfulChanges = statusChanged || progressChanged || textChanged || summaryChanged || summaryCountChanged || segmentsCountChanged
            
            // Если ничего реально не поменялось - тихо выходим. Объект не переприсваивается, UI не дергается!
            if !hasMeaningfulChanges {
                if updatedLecture.status == "completed" {
                    if updatedLecture.temporaryAudioURL != nil && (self.lecture.localAudioPath == nil || self.lecture.localAudioPath?.isEmpty == true) {
                        self.fetchTemporaryAudioIfNeeded(context: context)
                    }
                    if self.isGeneratingSummary {
                        withAnimation { self.isGeneratingSummary = false }
                    }
                }
                return
            }
            
            // ОБНОВЛЕНИЕ: Если данные физически изменились, обновляем UI
            withAnimation(.spring()) {
                var newLecture = updatedLecture
                newLecture.localAudioPath = self.lecture.localAudioPath
                
                if isGeneratingSummary && (newLecture.status == "completed" || newLecture.status == "ready" || newLecture.status == "error") {
                    self.isGeneratingSummary = false
                }
                
                self.lecture = newLecture
            }
            
            // ОБНОВЛЕНИЕ БД: Функция сама проверит, нужно ли вызывать save()
            updateLocalLecture(updatedLecture, context: context)
            
            // ПОСТ-ОБРАБОТКА СТАТУСОВ
            if updatedLecture.status == "completed" {
                cleanUp()
                if self.isGeneratingSummary { self.isGeneratingSummary = false }
                
                if updatedLecture.temporaryAudioURL != nil && (self.lecture.localAudioPath == nil || self.lecture.localAudioPath?.isEmpty == true) {
                    self.fetchTemporaryAudioIfNeeded(context: context)
                }
            } else if updatedLecture.status == "error" || updatedLecture.status == "canceled" {
                cleanUp()
                if self.isGeneratingSummary { self.isGeneratingSummary = false }
            }
            
        } catch {
            print("Ошибка синхронизации: \(error)")
        }
    }
    
    func updateSegment(id: UUID, newText: String, context: ModelContext) {
        guard var segments = lecture.segments,
              let index = segments.firstIndex(where: { $0.id == id }) else { return }
        
        segments[index].text = newText
        lecture.segments = segments
        
        let newFullText = segments.map { $0.text }.joined(separator: " ")
        lecture.fullText = newFullText
        
        updateLocalLecture(lecture, context: context)

        Task {
            try? await service.updateLecture(id: lecture.id, fullText: newFullText, segments: segments)
        }
    }
    
    private func updateLocalLecture(_ dto: LectureDTO, context: ModelContext) {
        let lectureID = dto.id
        let descriptor = FetchDescriptor<LocalLecture>(predicate: #Predicate<LocalLecture> { $0.id == lectureID })
        
        if let local = try? context.fetch(descriptor).first {
            var hasChanges = false
            
            // Точечная проверка каждого поля перед мутацией
            if local.title != dto.title { local.title = dto.title; hasChanges = true }
            if local.fullText != dto.fullText { local.fullText = dto.fullText; hasChanges = true }
            if local.summary != dto.summary { local.summary = dto.summary; hasChanges = true }
            
            let newStatus = dto.status ?? "completed"
            if local.status != newStatus { local.status = newStatus; hasChanges = true }
            
            let newProgress = dto.progress ?? 0.0
            if abs((local.progress ?? 0.0) - newProgress) > 0.001 { local.progress = newProgress; hasChanges = true }
            
            // Конвертация массивов в JSON и их сравнение
            if let history = dto.summaryHistory,
               let jsonData = try? JSONEncoder().encode(history),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if local.summaryHistoryJSON != jsonString {
                    local.summaryHistoryJSON = jsonString
                    hasChanges = true
                }
            }
            
            if let segments = dto.segments,
               let jsonData = try? JSONEncoder().encode(segments),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if local.segmentsJSON != jsonString {
                    local.segmentsJSON = jsonString
                    hasChanges = true
                }
            }
            
            if hasChanges {
                try? context.save()
            }
        }
    }
    
    func updateDatabasePath(newPath: String, context: ModelContext) {
        let id = lecture.id
        let descriptor = FetchDescriptor<LocalLecture>(predicate: #Predicate { $0.id == id })
        if let local = try? context.fetch(descriptor).first {
            local.localAudioPath = newPath
            try? context.save()
        }
    }
    
    private func getFileURL(fileName: String) -> URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
    }
    
    func cleanUp() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    func fetchTemporaryAudioIfNeeded(context: ModelContext) {
        guard let urlString = lecture.temporaryAudioURL,
              let url = URL(string: urlString),
              (lecture.localAudioPath == nil || lecture.localAudioPath?.isEmpty == true),
              !isDownloadingAudio else { return }
        
        isDownloadingAudio = true
        
        Task {
            do {
                if let dummyURL = URL(string: "https://api.vtuza.us/api/lectures") {
                    let dummyReq = URLRequest(url: dummyURL)
                    _ = try? await APIClient.shared.request(dummyReq)
                }
                
                var request = URLRequest(url: url)
                // Теперь в Keychain точно лежит свежий токен!
                if let token = KeychainManager.shared.getAccessToken() {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                
                let (tempLocalUrl, response) = try await URLSession.shared.download(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                
                let fileName = "\(UUID().uuidString).m4a"
                let destinationUrl = getFileURL(fileName: fileName)
                try FileManager.default.moveItem(at: tempLocalUrl, to: destinationUrl)
                
                await MainActor.run {
                    self.updateDatabasePath(newPath: fileName, context: context)
                    self.lecture.localAudioPath = fileName
                    self.isDownloadingAudio = false
                    self.hasLocalAudio = true
                }
                
                var deleteReq = URLRequest(url: url)
                deleteReq.httpMethod = "DELETE"
                if let token = KeychainManager.shared.getAccessToken() {
                    deleteReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                _ = try? await URLSession.shared.data(for: deleteReq)
                
            } catch {
                print("Download error: \(error)")
                await MainActor.run { self.isDownloadingAudio = false }
            }
        }
    }
}
