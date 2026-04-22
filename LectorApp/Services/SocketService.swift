import Foundation
import Combine

class SocketService: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    
    @Published var transcription: String = ""
    @Published var isConnected: Bool = false
    
    var onConnected: (() -> Void)?
    var onTextReceived: ((String) -> Void)?
    var onDisconnect: ((Error?) -> Void)? 
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func connect(language: String, token: String) {
        if session == nil {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        
        let safeToken = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
        let urlString = "wss://api.vtuza.us/ws/transcribe?lang=\(language)&token=\(safeToken)"
        guard let url = URL(string: urlString) else { return }
        
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("--- DEBUG: WebSocket ОТКРЫТ ---")
        DispatchQueue.main.async {
            self.isConnected = true
            self.onConnected?()
        }
    }
    
    func sendAudioData(_ data: Data) {
        guard let socket = webSocket, isConnected, socket.state == .running else { return }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        socket.send(message) { error in
            if let error = error {
                print("--- [SOCKET] Ошибка отправки аудио: \(error) ---")
            }
        }
    }
    
    func sendMessage(_ message: String) {
        guard let socket = webSocket, isConnected, socket.state == .running else { return }
        
        let textMessage = URLSessionWebSocketTask.Message.string(message)
        socket.send(textMessage) { error in
            if let error = error {
                print("--- [SOCKET] Ошибка отправки текста: \(error) ---")
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async {
                        self?.onTextReceived?(text)
                    }
                default: break
                }
                self?.receiveMessage()
            case .failure(let error):
                print("--- [SOCKET] Ошибка или закрытие: \(error) ---")
                DispatchQueue.main.async {
                    self?.onDisconnect?(error)
                }
                self?.disconnect()
            }
        }
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        session?.invalidateAndCancel()
        session = nil
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
