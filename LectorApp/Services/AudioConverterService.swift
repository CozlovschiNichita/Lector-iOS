import Foundation
import AVFoundation
import Combine

enum AudioFormat {
    case m4a
    case wav
    
    var extensionName: String {
        switch self {
        case .m4a: return "m4a"
        case .wav: return "wav"
        }
    }
}

class AudioConverterService: ObservableObject {
    @Published var exportProgress: Float = 0.0
    @Published var isExporting: Bool = false
    
    func convert(sourceURL: URL, to format: AudioFormat, completion: @escaping (URL?) -> Void) {
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension(format.extensionName)
        
        try? FileManager.default.removeItem(at: outputURL)
        
        if format == .wav {
            // Для WAV используем AVAudioFile (самый надежный способ для PCM)
            convertUsingAudioFile(sourceURL: sourceURL, destinationURL: outputURL, completion: completion)
        } else {
            // Для M4A используем стандартный экспорт
            convertUsingExportSession(sourceURL: sourceURL, destinationURL: outputURL, completion: completion)
        }
    }
    
    // Метод для создания идеального WAV
    private func convertUsingAudioFile(sourceURL: URL, destinationURL: URL, completion: @escaping (URL?) -> Void) {

        DispatchQueue.main.async {
            self.isExporting = true
            self.exportProgress = 0.0
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sourceFile = try AVAudioFile(forReading: sourceURL)
                let format = sourceFile.processingFormat
                
                // Настройки для классического WAV (16-bit PCM)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: format.sampleRate,
                    AVNumberOfChannelsKey: format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsNonInterleaved: false,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                
                let destinationFile = try AVAudioFile(forWriting: destinationURL, settings: settings)
                
                let totalFrames = sourceFile.length
                let bufferSize = AVAudioFrameCount(32768) // Читаем небольшими кусками
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
                    throw NSError(domain: "AudioConversion", code: 1, userInfo: nil)
                }
                
                var currentFrame: AVAudioFramePosition = 0
                
                // Цикл чтения-записи кусками
                while currentFrame < totalFrames {
                    let framesToRead = AVAudioFrameCount(min(AVAudioFramePosition(bufferSize), totalFrames - currentFrame))
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try destinationFile.write(from: buffer)
                    
                    currentFrame += AVAudioFramePosition(framesToRead)
                    
                    // Вычисляем прогресс и обновляем UI
                    let progress = Float(currentFrame) / Float(totalFrames)
                    DispatchQueue.main.async {
                        self.exportProgress = progress
                    }
                }
                
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(destinationURL)
                }
                
            } catch {
                print("--- [WAV ERROR] Ошибка: \(error.localizedDescription) ---")
                DispatchQueue.main.async {
                    self.isExporting = false
                    completion(nil)
                }
            }
        }
    }
    
    // Метод для создания M4A
    private func convertUsingExportSession(sourceURL: URL, destinationURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil)
            return
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .m4a
        
        DispatchQueue.main.async {
            self.isExporting = true
            self.exportProgress = 0.0
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                self.exportProgress = exportSession.progress
            }
        }
        
        exportSession.exportAsynchronously {
            timer.invalidate()
            DispatchQueue.main.async {
                self.isExporting = false
                if exportSession.status == .completed {
                    completion(destinationURL)
                } else {
                    print("--- [M4A ERROR] \(exportSession.error?.localizedDescription ?? "Unknown") ---")
                    completion(nil)
                }
            }
        }
    }
}
