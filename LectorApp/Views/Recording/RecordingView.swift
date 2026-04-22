import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import Combine

struct RecordingView: View {
    @Binding var selectedTab: Int
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = RecordingViewModel()
    @StateObject private var importService = ImportService()
    
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    @AppStorage("aiLanguage") private var aiLanguage: String = "ru"
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    @Environment(\.colorScheme) private var colorScheme
    
    @Query private var allLectures: [LocalLecture]
    
    private var processingLectures: [LocalLecture] {
        let currentUserID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""
        return allLectures.filter { lecture in
            guard lecture.ownerID == currentUserID else { return false }
            let status = lecture.status ?? ""
            
            if status == "uploading" || status == "waiting_for_network" || status == "waiting_in_queue" {
                return true
            }
            if status == "processing" {
                let text = lecture.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty || text == "Ожидает расшифровки..."
            }
            return false
        }
    }
    
    @State private var timeElapsed: TimeInterval = 0.0
    @State private var timer: Timer?
    @State private var isProcessingTail = false
    
    // переменные для 60 FPS и точного времени
    @State private var recordStartTime: Date?
    @State private var savedTime: TimeInterval = 0.0
    
    @State private var isFilePickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isExtractingAudio = false
    
    @State private var showYouTubeAlert = false
    @State private var youtubeLink = ""
    
    @State private var showPlusMenu = false
    @State private var settingsRotation: Double = 0
    @State private var showSettings = false
    @State private var showOfflineAlert = false
    
    @State private var showInfoAlert = false
    @State private var infoAlertMessage = ""
    
    @State private var showProcessingQueue = false
    @State private var showCancelProcessingAlert = false
    @State private var lectureToCancel: LocalLecture?
    
    @State private var syncTimer = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    private let maxFileSize: Int64 = 1_500_000_000
    private let maxRecordingTime: TimeInterval = 7200

    // MARK: - ВЫЧИСЛЯЕМЫЕ СВОЙСТВА ДЛЯ РАЗГРУЗКИ КОМПИЛЯТОРА (Исправление ошибки type-check)
    
    private var isRecordingOrPaused: Bool {
        timeElapsed > 0 || viewModel.isRecording
    }
    
    private var timerColor: Color {
        if viewModel.isRecording { return .red }
        if timeElapsed > 0 { return .orange }
        return .primary
    }
    
    private var resolvedColorScheme: ColorScheme? {
        if appTheme == "dark" { return .dark }
        if appTheme == "light" { return .light }
        return colorScheme
    }
    
    private var bannerColor: Color {
        let onlyNetworkWaiting = processingLectures.allSatisfy { $0.status == "waiting_for_network" }
        return onlyNetworkWaiting ? .orange : .blue
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // --- БАННЕР ЗАГРУЗКИ ФАЙЛА ---
                if importService.isUploading {
                    VStack(spacing: 8) {
                        HStack {
                            ProgressView(value: importService.uploadProgress, total: 1.0)
                                .tint(.white)
                            Text("\(Int(importService.uploadProgress * 100))%")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Идет загрузка на сервер...")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Не закрывайте и не сворачивайте приложение!")
                                    .font(.system(size: 10, weight: .medium))
                                    .opacity(0.8)
                            }
                        }
                        .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(16)
                    .padding([.horizontal, .top])
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // --- КНОПКА ОЧЕРЕДИ / БАННЕР ОБРАБОТКИ ---
                if !processingLectures.isEmpty {
                    processingBanner
                        .onTapGesture { showProcessingQueue = true }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // --- ТАЙМЕР ---
                VStack(spacing: 4) {
                    Text(formatTime(timeElapsed))
                        .font(.system(size: 44, weight: .semibold, design: .monospaced))
                        .foregroundColor(timerColor) // Используем простую переменную
                    
                    if !viewModel.isRecording && timeElapsed > 0 {
                        Text("ПАУЗА")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(.orange)
                            .tracking(2)
                    }
                }
                .frame(height: 80)
                .padding(.top, 20)
                
                // --- ТЕКСТОВАЯ ОБЛАСТЬ ---
                transcriptionArea
                    .padding()
                    .zIndex(0)
                
                // --- ВОЛНА ---
                if isRecordingOrPaused { // Используем простую переменную
                    waveformSection
                        .frame(height: 100)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
                
                // --- ЯЗЫК ---
                if timeElapsed == 0 && !viewModel.isRecording {
                    languagePickerPlashka
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(1)
                }
                
                // --- ПАНЕЛЬ УПРАВЛЕНИЯ ---
                ControlPanel(
                    timeElapsed: timeElapsed,
                    viewModel: viewModel,
                    importService: importService,
                    globalPlayer: GlobalAudioPlayer.shared,
                    isExtractingAudio: isExtractingAudio,
                    processingLecturesCount: processingLectures.count,
                    isProcessingTail: isProcessingTail,
                    onTrash: {
                        withAnimation {
                            fullReset()
                            viewModel.cancelRecording()
                        }
                    },
                    onPlus: { showPlusMenu = true },
                    onToggleRecord: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            handleToggleRecording()
                        }
                    },
                    onSave: {
                        withAnimation {
                            autoSaveAndReset()
                        }
                    }
                )
                MiniPlayerContainer()
                    .zIndex(100)
            }
            .animation(.easeInOut(duration: 0.4), value: isRecordingOrPaused) // Используем простую переменную
            .navigationTitle("Запись")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        withAnimation(.linear(duration: 0.5)) { settingsRotation += 180 }
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .rotationEffect(.degrees(settingsRotation))
                            .foregroundColor(.primary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    OfflineIndicator()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .preferredColorScheme(resolvedColorScheme) // Используем простую переменную
            }
            .sheet(isPresented: $showPlusMenu) {
                ImportMenuSheet(
                    aiLanguage: $aiLanguage,
                    showPlusMenu: $showPlusMenu,
                    isFilePickerPresented: $isFilePickerPresented,
                    showOfflineAlert: $showOfflineAlert,
                    showYouTubeAlert: $showYouTubeAlert,
                    selectedPhotoItem: $selectedPhotoItem
                )
                .presentationDetents([.height(450), .medium])
            }
            .sheet(isPresented: $showProcessingQueue) {
                ProcessingQueueSheet(
                    processingLectures: processingLectures,
                    showProcessingQueue: $showProcessingQueue,
                    lectureToCancel: $lectureToCancel,
                    showCancelProcessingAlert: $showCancelProcessingAlert
                )
                .presentationDetents([.medium, .large])
            }
            .onChange(of: viewModel.isRecording) { isRecordingNow in
                if isRecordingNow {
                    startTimer()
                } else {
                    stopTimer()
                }
            }
            .onChange(of: networkMonitor.isConnected) { connected in
                if connected {
                    Task {
                        await syncProcessingLectures()
                    }
                }
            }
            .onAppear { viewModel.setupContext(modelContext) }
            .onReceive(syncTimer) { _ in
                if !processingLectures.isEmpty && networkMonitor.isConnected {
                    Task { await syncProcessingLectures() }
                }
            }
            .fileImporter(
                isPresented: $isFilePickerPresented,
                allowedContentTypes: [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .onChange(of: selectedPhotoItem) { newItem in
                if newItem != nil {
                    if networkMonitor.isConnected {
                        showPlusMenu = false
                        handleVideoImport(item: newItem)
                    } else {
                        selectedPhotoItem = nil
                        showOfflineAlert = true
                    }
                }
            }
            .alert("Импорт из YouTube", isPresented: $showYouTubeAlert) {
                TextField("Вставьте ссылку", text: $youtubeLink)
                Button("Отмена", role: .cancel) { youtubeLink = "" }
                Button("Импортировать") {
                    if !youtubeLink.isEmpty { handleYouTubeImport() }
                }
            } message: {
                Text("Видео будет расшифровано на языке: \(languageName(for: aiLanguage)). Ограничение по длительности - 2 часа.")
            }
            .alert("Внимание", isPresented: $showInfoAlert) {
                Button("ОК", role: .cancel) { }
            } message: {
                Text(infoAlertMessage)
            }
            .alert("Отменить транскрипцию?", isPresented: $showCancelProcessingAlert) {
                Button("Назад", role: .cancel) { lectureToCancel = nil }
                Button("Отменить процесс", role: .destructive) {
                    if let lecture = lectureToCancel { cancelProcessing(lecture) }
                }
            }
        }
    }
    
    // MARK: - Вспомогательные View
    private var languagePickerPlashka: some View {
        Menu {
            Picker("Язык", selection: $aiLanguage) {
                Text("English").tag("en")
                Text("Русский").tag("ru")
                Text("Română").tag("ro")
                Text("Français").tag("fr")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "waveform.and.mic")
                Text("Язык речи: \(languageName(for: aiLanguage))")
                Image(systemName: "chevron.up.chevron.down")
            }
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .clipShape(Capsule())
        }
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private func languageName(for code: String) -> String {
        switch code {
        case "en": return "English"
        case "ru": return "Русский"
        case "ro": return "Română"
        case "fr": return "Français"
        default: return code
        }
    }
    
    private var processingBanner: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("В обработке: \(processingLectures.count)")
                    .font(.subheadline.bold())
                
                if let first = processingLectures.first {
                    Text(first.status == "waiting_for_network" ? "Ожидание интернета..." : "ИИ расшифровывает аудио...")
                        .font(.caption).opacity(0.8)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .opacity(0.5)
        }
        .padding(14)
        .background(bannerColor) // Используем простую переменную
        .foregroundColor(.white)
        .cornerRadius(16)
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var transcriptionArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.isFinalizing {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5).tint(.blue)
                        Text("Сохраняем лекцию...").font(.headline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    Text(viewModel.transcription.isEmpty ? String(localized: "Здесь появится текст лекции...") : viewModel.transcription)
                        .font(.system(.body, design: .rounded))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(viewModel.transcription.isEmpty ? .secondary : .primary)
                        .id("bottom")
                }
            }
            .background(Color(UIColor.systemGray6))
            .cornerRadius(24)
            .onChange(of: viewModel.transcription) { _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
    
    // МАРК: секция волны. Отображается только по условию выше.
    private var waveformSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(UIColor.secondarySystemBackground))
            
            WaveformView(
                audioLevel: viewModel.audioLevel,
                isRecording: viewModel.isRecording,
                timeElapsed: timeElapsed
            )
            .padding(.horizontal)
            .opacity(viewModel.isRecording ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Логика управления записью
    private func handleToggleRecording() {
        viewModel.toggleRecording(language: aiLanguage, isConnected: networkMonitor.isConnected)
    }
    
    private func autoSaveAndReset() {
        if viewModel.isRecording { viewModel.toggleRecording(language: aiLanguage, isConnected: networkMonitor.isConnected) }
        isProcessingTail = true
        stopTimer()
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                viewModel.finalizeAndSave()
                fullReset()
                isProcessingTail = false
            }
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        recordStartTime = Date()
        
        let newTimer = Timer(timeInterval: 0.016, repeats: true) { _ in
            if let start = recordStartTime {
                timeElapsed = savedTime + Date().timeIntervalSince(start)
                
                if timeElapsed >= maxRecordingTime {
                    autoSaveAndReset()
                    infoAlertMessage = "Лимит записи (2 часа) достигнут."
                    showInfoAlert = true
                }
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        if let start = recordStartTime {
            savedTime += Date().timeIntervalSince(start)
        }
        recordStartTime = nil
    }
    
    private func fullReset() {
        stopTimer()
        savedTime = 0.0
        timeElapsed = 0.0
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d,%02d", minutes, seconds, ms)
    }
    
    // MARK: - СИНХРОНИЗАЦИЯ С СЕРВЕРОМ
    private func syncProcessingLectures() async {
        guard let token = KeychainManager.shared.getAccessToken() else { return }
        let url = URL(string: "https://api.vtuza.us/api/lectures")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let serverLectures = try decoder.decode([LectureDTO].self, from: data)
            
            await MainActor.run {
                var hasChanges = false // Отслеживаем реальные изменения
                
                for processing in processingLectures {
                    if let serverMatch = serverLectures.first(where: { $0.id == processing.id }) {
                        if processing.progress != serverMatch.progress || processing.status != serverMatch.status {
                            processing.progress = serverMatch.progress
                            processing.status = serverMatch.status
                            hasChanges = true
                        }
                    }
                }
                
                if hasChanges {
                    try? modelContext.save()
                }
            }
        } catch { }
    }
    
    // MARK: - ИМПОРТ ФАЙЛОВ
    
    private func handleFileImport(result: Result<[URL], Error>) {
        if case .success(let urls) = result, let url = urls.first {
            guard url.startAccessingSecurityScopedResource() else { return }
            
            let ext = url.pathExtension.lowercased()
            let allowed = ["mp3", "m4a", "wav", "aac", "mp4", "mov"]
            if !allowed.contains(ext) {
                url.stopAccessingSecurityScopedResource()
                infoAlertMessage = "Формат .\(ext) не поддерживается."
                showInfoAlert = true
                return
            }
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.copyItem(at: url, to: tempURL)
            url.stopAccessingSecurityScopedResource()
            
            Task {
                let isVideo = ["mp4", "mov", "m4v", "avi"].contains(tempURL.pathExtension.lowercased())
                if isVideo {
                    isExtractingAudio = true
                    importService.extractAudio(from: tempURL) { audioURL in
                        isExtractingAudio = false
                        if let audioURL = audioURL { startUpload(at: audioURL) }
                    }
                } else {
                    startUpload(at: tempURL)
                }
            }
        }
    }
    
    private func startUpload(at url: URL) {
        Task {
            do {
                _ = try await importService.uploadFile(at: url, language: aiLanguage) { startDTO in
                    Task { @MainActor in saveNewLectureLocally(startDTO, sourceURL: url) }
                }
            } catch {
                infoAlertMessage = "Ошибка при загрузке файла."
                showInfoAlert = true
            }
        }
    }
    
    private func saveNewLectureLocally(_ dto: LectureDTO, sourceURL: URL? = nil) {
        var finalAudioPath: String? = nil
        let currentUserID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""

        if let source = sourceURL, source.isFileURL {
            let fileName = "\(UUID().uuidString).\(source.pathExtension)"
            let destURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: source, to: destURL)
            finalAudioPath = fileName
        }

        let local = LocalLecture(
            id: dto.id,
            title: dto.title,
            fullText: dto.fullText,
            summary: dto.summary,
            createdAt: dto.createdAt ?? Date(),
            ownerID: currentUserID
        )
        local.status = dto.status ?? "uploading"
        local.progress = dto.progress ?? 0.0
        local.folderID = dto.folderID
        local.localAudioPath = finalAudioPath
        
        modelContext.insert(local)
        try? modelContext.save()
    }

    private func handleVideoImport(item: PhotosPickerItem?) {
        guard let item = item else { return }
        isExtractingAudio = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_video.mov")
                try? data.write(to: tempURL)
                importService.extractAudio(from: tempURL) { url in
                    isExtractingAudio = false
                    if let audioURL = url { startUpload(at: audioURL) }
                }
            } else { isExtractingAudio = false }
        }
    }
    
    private func handleYouTubeImport() {
        let link = youtubeLink
        youtubeLink = ""
        Task {
            do {
                _ = try await importService.uploadYouTube(link: link, language: aiLanguage) { startDTO in
                    Task { @MainActor in saveNewLectureLocally(startDTO, sourceURL: nil) }
                }
            } catch {
                infoAlertMessage = "Не удалось загрузить видео из YouTube."
                showInfoAlert = true
            }
        }
    }
    
    private func cancelProcessing(_ lecture: LocalLecture) {
        let id = lecture.id
        lecture.status = "canceled"
        try? modelContext.save()
        Task {
            guard let token = KeychainManager.shared.getAccessToken(),
                  let url = URL(string: "https://api.vtuza.us/api/import/cancel/\(id)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

struct MiniPlayerContainer: View {
    @ObservedObject var globalPlayer = GlobalAudioPlayer.shared
    
    var body: some View {
        if let title = globalPlayer.currentLectureTitle, !title.isEmpty {
            MiniPlayerView()
                .transition(.move(edge: .bottom))
        }
    }
}
