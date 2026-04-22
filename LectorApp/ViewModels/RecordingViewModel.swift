import Foundation
import Combine
import SwiftData

@MainActor
class RecordingViewModel: ObservableObject {
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isFinalizing = false
    @Published var audioLevel: Float = 0.0
    @Published var connectionError: String?
    
    @Published var isRecordingOffline = false
    
    private var finalizedText: String = ""
    private let socketService = SocketService()
    private let audioService = AudioService() // Изолированный сервис работы со звуком
    private var modelContext: ModelContext?
    
    var currentAudioURL: URL?
    
    private var audioDataBuffer = Data()
    private var lastSendTime = Date()
    private let sendInterval: TimeInterval = 2.0
    private let processingQueue = DispatchQueue(label: "com.lectorapp.audioprocessing")
    
    init() {
        setupSocketBindings()
        setupAudioBindings()
    }
    
    func setupContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    private func setupAudioBindings() {
        audioService.onVolumeUpdate = { [weak self] level in
            DispatchQueue.main.async { self?.audioLevel = level }
        }
        
        audioService.onAudioData = { [weak self] data in
            guard let self = self, !self.isRecordingOffline else { return }
            
            self.processingQueue.async {
                self.audioDataBuffer.append(data)
                
                if Date().timeIntervalSince(self.lastSendTime) >= self.sendInterval {
                    let chunkToSend = self.audioDataBuffer
                    self.audioDataBuffer.removeAll()
                    self.socketService.sendAudioData(chunkToSend)
                    self.lastSendTime = Date()
                }
            }
        }
    }
    
    private func setupSocketBindings() {
        socketService.onTextReceived = { [weak self] text in
            Task { @MainActor in
                guard let self = self else { return }
                
                if text.hasPrefix("SAVED_ID:") {
                    self.handleServerConfirmation(message: text)
                } else if text.hasPrefix("[PARTIAL]") {
                    let partial = text.replacingOccurrences(of: "[PARTIAL]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let space = self.finalizedText.isEmpty ? "" : " "
                    self.transcription = self.finalizedText + space + partial
                } else if text.hasPrefix("[FINAL]") {
                    let final = text.replacingOccurrences(of: "[FINAL]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let space = self.finalizedText.isEmpty ? "" : " "
                    self.finalizedText += space + final
                    self.transcription = self.finalizedText
                }
            }
        }
        
        socketService.onDisconnect = { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isFinalizing {
                    self.saveOfflineLecture()
                } else if self.isRecording {
                    self.isRecordingOffline = true
                    self.connectionError = String(localized: "Связь потеряна. Расшифровка приостановлена, но аудио продолжает записываться.")
                }
            }
        }
    }
    
    func toggleRecording(language: String, isConnected: Bool) {
        if isRecording { pauseRecording() } else { startRecording(language: language, isConnected: isConnected) }
    }

    private func startRecording(language: String, isConnected: Bool) {
        Task {
            var tokenForSocket: String? = nil
            
            if isConnected {
                // Если у тебя нет метода ensureValidToken, мы просто берем токен из Keychain
                tokenForSocket = KeychainManager.shared.getAccessToken()
                if tokenForSocket == nil {
                    await MainActor.run {
                        self.connectionError = String(localized: "Сессия истекла. Пожалуйста, авторизуйтесь заново.")
                    }
                    return
                }
            }
            
            await MainActor.run {
                GlobalAudioPlayer.shared.stop()
                GlobalAudioPlayer.shared.isMicActive = true // Блокируем плеер!
                self.connectionError = nil
                self.isRecordingOffline = !isConnected

                if isConnected, let validToken = tokenForSocket {
                    self.socketService.connect(language: language, token: validToken)
                } else {
                    self.connectionError = String(localized: "Офлайн-режим. Аудио будет сохранено и расшифровано позже.")
                }

                if self.currentAudioURL == nil {
                    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    self.currentAudioURL = docsDir.appendingPathComponent("\(UUID().uuidString).m4a")
                    self.transcription = ""
                    self.finalizedText = ""
                }

                do {
                    try self.audioService.startCapturing(to: self.currentAudioURL!)
                    self.isRecording = true
                } catch {
                    self.connectionError = String(localized: "Ошибка доступа к микрофону.")
                }
            }
        }
    }

    private func pauseRecording() {
        audioService.stopCapturing()
        isRecording = false
        GlobalAudioPlayer.shared.isMicActive = false // Снимаем блокировку
        
        if !isRecordingOffline {
            processingQueue.async {
                if !self.audioDataBuffer.isEmpty {
                    self.socketService.sendAudioData(self.audioDataBuffer)
                    self.audioDataBuffer.removeAll()
                }
                self.socketService.sendMessage("FLUSH_BUFFER")
            }
        }
    }
    
    func finalizeAndSave() {
        isFinalizing = true
        if isRecording { pauseRecording() }
        
        if isRecordingOffline {
            saveOfflineLecture()
            return
        }
        
        processingQueue.async {
            if !self.audioDataBuffer.isEmpty {
                self.socketService.sendAudioData(self.audioDataBuffer)
                self.audioDataBuffer.removeAll()
            }
            self.socketService.sendMessage("FINISH_AND_SAVE_LECTURE")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) { [weak self] in
            guard let self = self else { return }
            if self.isFinalizing {
                self.saveOfflineLecture()
            }
        }
    }

    private func handleServerConfirmation(message: String) {
        let components = message.components(separatedBy: ":")
        guard components.count == 2, let serverUUID = UUID(uuidString: components[1]), let context = modelContext else {
            isFinalizing = false
            return
        }
        
        let currentID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""
        let finalTrans = transcription.isEmpty ? finalizedText : transcription
        
        // Правильная локализация названия
        let localizedTitle = String(localized: "Лекция")
        
        let localLecture = LocalLecture(
            id: serverUUID,
            title: "\(localizedTitle) \(Date().formatted(date: .abbreviated, time: .shortened))",
            fullText: finalTrans,
            ownerID: currentID
        )
        localLecture.localAudioPath = currentAudioURL?.lastPathComponent
        
        context.insert(localLecture)
        try? context.save()
        
        isFinalizing = false
        clearRecording()
    }
    
    private func saveOfflineLecture() {
        guard let context = modelContext else { return }
        
        let localID = UUID()
        let currentID = UserDefaults.standard.string(forKey: "current_user_id") ?? ""
        let finalTrans = transcription.isEmpty ? finalizedText : transcription
        
        // Правильная локализация названия
        let localizedTitle = String(localized: "Офлайн-запись")
        let waitingText = String(localized: "Ожидает расшифровки...")
        
        let localLecture = LocalLecture(
            id: localID,
            title: "\(localizedTitle) \(Date().formatted(date: .abbreviated, time: .shortened))",
            fullText: finalTrans.isEmpty ? waitingText : finalTrans,
            ownerID: currentID
        )
        localLecture.localAudioPath = currentAudioURL?.lastPathComponent
        
        localLecture.status = "waiting_for_network"
        localLecture.progress = 0.0
        
        context.insert(localLecture)
        try? context.save()
        
        isFinalizing = false
        socketService.disconnect()
        clearRecording()
    }
    
    func cancelRecording() {
        if isRecording { pauseRecording() }
        socketService.disconnect()
        clearRecording()
    }
    
    func clearRecording() {
        transcription = ""
        finalizedText = ""
        processingQueue.async { self.audioDataBuffer.removeAll() }
        audioLevel = 0.0
        currentAudioURL = nil
        isRecording = false
        GlobalAudioPlayer.shared.isMicActive = false // Снимаем блокировку
        isRecordingOffline = false
        connectionError = nil
    }
}
