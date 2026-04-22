import Foundation
import AVFoundation

class AudioService {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var whisperConverter: AVAudioConverter?
    
    // Коллбеки для передачи данных во ViewModel
    var onAudioData: ((Data) -> Void)?
    var onVolumeUpdate: ((Float) -> Void)?
    
    func startCapturing(to fileURL: URL) throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        
        // Целевой формат для Whisper (16 kHz, Float32, Mono)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        whisperConverter = AVAudioConverter(from: nativeFormat, to: targetFormat)
        
        // Настройка локального файла (сохраняем оригинал в AAC/M4A)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: nativeFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // 1. Пишем оригинальный звук в файл
            try? self.audioFile?.write(from: buffer)
            
            // 2. Считаем громкость для анимации в UI
            self.calculateVolume(buffer: buffer)
            
            // 3. Конвертируем для Whisper и отдаем байты
            self.processForWhisper(buffer: buffer, nativeFormat: nativeFormat, targetFormat: targetFormat)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        print("--- Микрофон начал запись. Сохранение в: \(fileURL.lastPathComponent) ---")
    }
    
    func stopCapturing() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioFile = nil // Закрываем файл
        try? AVAudioSession.sharedInstance().setActive(false)
        print("--- Микрофон остановлен ---")
    }
    
    // MARK: - Внутренняя обработка
    
    private func calculateVolume(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let channelDataArray = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
        
        let sumOfSquares = channelDataArray.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(channelDataArray.count))
        let noiseFloor: Float = 0.01
        let normalized = rms < noiseFloor ? 0.0 : min(rms * 3.0, 1.0)
        
        onVolumeUpdate?(normalized)
    }
    
    private func processForWhisper(buffer: AVAudioPCMBuffer, nativeFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        let ratio = targetFormat.sampleRate / nativeFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        
        var error: NSError?
        var dataProvided = false
        
        whisperConverter?.convert(to: targetBuffer, error: &error) { _, outStatus in
            if dataProvided {
                outStatus.pointee = .noDataNow
                return nil
            }
            dataProvided = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        guard error == nil, let channelData = targetBuffer.floatChannelData?[0] else { return }
        
        let byteCount = Int(targetBuffer.frameLength) * MemoryLayout<Float>.size
        let data = Data(bytes: channelData, count: byteCount)
        
        onAudioData?(data)
    }
}
