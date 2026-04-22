import Foundation
import AVFoundation
import Combine

actor UploadQueue {
    private var previousTask: Task<Void, Never>?
    
    func enqueue<T>(operation: @escaping () async throws -> T) async throws -> T {
        let task = Task<T, Error> { [previousTask] in
            _ = await previousTask?.value
            return try await operation()
        }
        previousTask = Task { _ = try? await task.value }
        return try await task.value
    }
}

class ImportService: NSObject, ObservableObject, URLSessionTaskDelegate {
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var isExtractingAudio = false
    
    private let uploadQueue = UploadQueue()
    private var fileUploadTask: Task<LectureDTO, Error>? = nil
    private var youtubeUploadTask: Task<LectureDTO, Error>? = nil
    
    // Специальная сессия с длинным таймаутом для больших файлов
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func uploadFile(at fileURL: URL, language: String, onStart: @escaping ((LectureDTO) -> Void)) async throws -> LectureDTO {
        let startURL = URL(string: "https://api.vtuza.us/api/import/start")!
        var startReq = URLRequest(url: startURL)
        startReq.httpMethod = "POST"
        startReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        startReq.httpBody = try JSONEncoder().encode(["filename": fileURL.lastPathComponent])
 
        let (sData, _) = try await APIClient.shared.request(startReq, session: self.session)
        let lecture = try decoder.decode(LectureDTO.self, from: sData)
        let lectureID = lecture.id.uuidString
        
        await MainActor.run { onStart(lecture) }
        
        try await uploadQueue.enqueue {
            await MainActor.run {
                self.isUploading = true
                self.uploadProgress = 0.0
            }
            
            let chunkSize = 5 * 1024 * 1024
            let fileData = try Data(contentsOf: fileURL)
            let totalSize = fileData.count
            var offset = 0
            
            while offset < totalSize {
                let chunkEnd = min(offset + chunkSize, totalSize)
                let chunkData = fileData.subdata(in: offset..<chunkEnd)
                
                var chunkReq = URLRequest(url: URL(string: "https://api.vtuza.us/api/import/chunk?lectureId=\(lectureID)")!)
                chunkReq.httpMethod = "POST"
                chunkReq.httpBody = chunkData
                
                _ = try await APIClient.shared.request(chunkReq, session: self.session)
                
                offset = chunkEnd
                let currentProgress = Double(offset) / Double(totalSize)
                await MainActor.run { self.uploadProgress = currentProgress * 0.9 }
            }
            
            var compReq = URLRequest(url: URL(string: "https://api.vtuza.us/api/import/complete?lectureId=\(lectureID)&lang=\(language)")!)
            compReq.httpMethod = "POST"
            
            _ = try await APIClient.shared.request(compReq, session: self.session)
            
            await MainActor.run {
                self.uploadProgress = 1.0
                self.isUploading = false
            }
        }
        
        return lecture
    }

    func uploadYouTube(link: String, language: String, onStart: @escaping ((LectureDTO) -> Void)) async throws -> LectureDTO {
        return try await uploadQueue.enqueue {
            await MainActor.run { self.isUploading = true }
            
            let url = URL(string: "https://api.vtuza.us/api/import/youtube")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["url": link, "lang": language])
            
            let (data, _) = try await APIClient.shared.request(req, session: self.session)
            let lecture = try self.decoder.decode(LectureDTO.self, from: data)
            
            await MainActor.run {
                onStart(lecture)
                self.isUploading = false
            }
            return lecture
        }
    }

    func cancelUpload() {
        fileUploadTask?.cancel()
        youtubeUploadTask?.cancel()
        isUploading = false
    }

    func extractAudio(from videoURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: videoURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .m4a
        DispatchQueue.main.async { self.isExtractingAudio = true }
        exportSession?.exportAsynchronously {
            DispatchQueue.main.async {
                self.isExtractingAudio = false
                completion(exportSession?.status == .completed ? outputURL : nil)
            }
        }
    }
}
