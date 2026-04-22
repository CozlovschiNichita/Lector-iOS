import SwiftUI
import Combine

struct MiniPlayerView: View {
    @ObservedObject var player = GlobalAudioPlayer.shared
    
    @State private var localTime: TimeInterval = 0
    @State private var isDragging: Bool = false
    
    // ЛОКАЛЬНЫЙ ТАЙМЕР
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                AnimatedWaveformView(isPlaying: player.isPlaying)
                    .frame(width: 30)
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.currentLectureTitle ?? "Нет аудио")
                        .font(.subheadline).bold()
                        .lineLimit(1)
                    
                    HStack {
                        Text(formatTime(localTime))
                        Text("-")
                        Text(formatTime(player.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button(action: {
                        player.seek(to: 0)
                        localTime = 0
                    }) {
                        Image(systemName: "backward.end.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                    
                    Button(action: { player.isPlaying ? player.pause() : player.resume() }) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(player.isMicActive)
                    .opacity(player.isMicActive ? 0.3 : 1.0)
                    
                    Button(action: { player.close() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            Slider(
                value: Binding(
                    get: { localTime },
                    set: { localTime = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { dragging in
                    isDragging = dragging
                    if !dragging {
                        let progress = player.duration > 0 ? localTime / player.duration : 0
                        player.seek(to: progress)
                    }
                }
            )
            .accentColor(.blue)
            .scaleEffect(y: 0.8)
            .padding(.horizontal, 16)
            .onReceive(timer) { _ in
                guard player.isPlaying && !isDragging else { return }
                localTime = player.currentTime
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN, !time.isInfinite else { return "00:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
