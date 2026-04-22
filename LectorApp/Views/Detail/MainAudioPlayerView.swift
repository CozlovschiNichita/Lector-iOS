import SwiftUI
import Combine

struct MainAudioPlayerView: View {
    @ObservedObject var player = GlobalAudioPlayer.shared
    let lecture: LectureDTO
    
    var isDownloadingAudio: Bool = false
    
    @State private var localTime: TimeInterval = 0
    @State private var isDragging: Bool = false
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    private var isThisPlaying: Bool {
        player.playingLecture?.id == lecture.id
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Заголовок аудио
            HStack {
                AnimatedWaveformView(isPlaying: isThisPlaying && player.isPlaying)
                    .frame(width: 40)
                
                VStack(alignment: .leading) {
                    Text(lecture.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Аудиозапись")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)

            if isDownloadingAudio {
                HStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(1.2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Загрузка аудиодорожки...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Синхронизация с сервером")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                
            } else {
                // Ползунок перемотки
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { isThisPlaying ? localTime : 0 },
                            set: { localTime = $0 }
                        ),
                        in: 0...max(isThisPlaying ? player.duration : 1, 1),
                        onEditingChanged: { dragging in
                            guard isThisPlaying else { return }
                            isDragging = dragging
                            if !dragging {
                                let progress = player.duration > 0 ? localTime / player.duration : 0
                                player.seek(to: progress)
                            }
                        }
                    )
                    .accentColor(.blue)
                    .disabled(!isThisPlaying)
                    .onReceive(timer) { _ in
                        // Обновляем UI только если ЭТА лекция сейчас реально играет
                        guard player.isPlaying && isThisPlaying else { return }
                        
                        // Если пользователь не тянет ползунок руками, обновляем время
                        if !isDragging {
                            localTime = player.currentTime
                        }
                    }
                    
                    // Таймеры
                    HStack {
                        Text(isThisPlaying ? formatTime(localTime) : "00:00")
                        Spacer()
                        Text(isThisPlaying ? formatTime(player.duration) : "--:--")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)
                }
                .padding(.horizontal)

                // Кнопки управления
                HStack(spacing: 45) {
                    // Начать заново
                    Button(action: {
                        if isThisPlaying {
                            player.seek(to: 0)
                            localTime = 0
                            if !player.isPlaying { player.resume() }
                        }
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .foregroundColor(isThisPlaying ? .primary : .gray.opacity(0.5))
                    }
                    .disabled(!isThisPlaying)
                    
                    // Плей / Пауза
                    Button(action: {
                        if !isThisPlaying {
                            player.play(lecture: lecture)
                        } else {
                            player.isPlaying ? player.pause() : player.resume()
                        }
                    }) {
                        Image(systemName: isThisPlaying && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                    }
                    .disabled(player.isMicActive)
                    .opacity(player.isMicActive ? 0.3 : 1.0)
                    
                    // Перемотка вперед
                    Button(action: {
                        if isThisPlaying {
                            let newTime = min(player.currentTime + 15, player.duration)
                            let progress = player.duration > 0 ? newTime / player.duration : 0
                            player.seek(to: progress)
                            localTime = newTime
                        }
                    }) {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                            .foregroundColor(isThisPlaying ? .primary : .gray.opacity(0.5))
                    }
                    .disabled(!isThisPlaying)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite else { return "00:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Анимированный эквалайзер
struct AnimatedWaveformView: View {
    var isPlaying: Bool
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            bar(height1: 10, height2: 24, delay: 0.0)
            bar(height1: 16, height2: 28, delay: 0.15)
            bar(height1: 12, height2: 20, delay: 0.3)
            bar(height1: 18, height2: 26, delay: 0.1)
            bar(height1: 8,  height2: 18, delay: 0.25)
        }
        .frame(height: 30)
        .onChange(of: isPlaying) { playing in
            isAnimating = playing
        }
        .onAppear {
            if isPlaying { isAnimating = true }
        }
    }

    func bar(height1: CGFloat, height2: CGFloat, delay: Double) -> some View {
        Capsule()
            .fill(Color.blue)
            .frame(width: 4, height: isAnimating ? height2 : height1)
            .animation(
                isPlaying
                    ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(delay)
                    : .easeInOut(duration: 0.2),
                value: isAnimating
            )
    }
}
