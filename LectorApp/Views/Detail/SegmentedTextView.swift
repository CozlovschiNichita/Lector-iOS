import SwiftUI
import Combine

// MARK: - Трекер активного сегмента
class ActiveSegmentTracker: ObservableObject {
    @Published var activeID: UUID?
    private var cancellable: AnyCancellable?
    
    func startTracking(segments: [TextSegment], player: GlobalAudioPlayer) {
        // Опрашиваем плеер и ищем текущий сегмент по времени
        cancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .map { _ in player.currentTime }
            .map { time in
                segments.last(where: { time >= $0.startTime && time < $0.endTime })?.id
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newID in
                self?.activeID = newID
            }
    }
    
    func stopTracking() {
        cancellable?.cancel()
        cancellable = nil
    }
}

// MARK: - Основной контейнер текста
struct SegmentedTextView: View {
    let segments: [TextSegment]
    @ObservedObject var viewModel: LectureDetailViewModel
    var onSeek: (TimeInterval) -> Void
    var onEdit: (UUID, String) -> Void
    
    @StateObject private var tracker = ActiveSegmentTracker()
    
    @State private var editingSegment: TextSegment?
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments, id: \.id) { segment in
                SegmentRowView(
                    segment: segment,
                    isActive: tracker.activeID == segment.id,
                    viewModel: viewModel, // Передаем VM внутрь строки
                    onSeek: onSeek,
                    onEditRequest: {
                        editText = segment.text
                        editingSegment = segment
                    }
                )
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            tracker.startTracking(segments: segments, player: GlobalAudioPlayer.shared)
        }
        .onDisappear {
            tracker.stopTracking()
        }
        // Перезапускаем трекер, если количество сегментов изменилось (например, пришла новая расшифровка)
        .onChange(of: segments.count) { _ in
            tracker.stopTracking()
            tracker.startTracking(segments: segments, player: GlobalAudioPlayer.shared)
        }
        // Лист редактирования
        .sheet(item: $editingSegment) { segment in
            NavigationView {
                TextEditor(text: $editText)
                    .padding(8)
                    .font(.body)
                    .navigationTitle("Редактирование")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { editingSegment = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Сохранить") {
                                onEdit(segment.id, editText)
                                editingSegment = nil
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Отдельная строка сегмента
struct SegmentRowView: View {
    let segment: TextSegment
    let isActive: Bool
    @ObservedObject var viewModel: LectureDetailViewModel // Добавили VM
    let onSeek: (TimeInterval) -> Void
    let onEditRequest: () -> Void
    
    var body: some View {
        Button(action: {
            onSeek(segment.startTime)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // Берем готовую подсвеченную строку из кэша ViewModel
                Text(viewModel.highlightedSegments[segment.id] ?? AttributedString(segment.text))
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(isActive ? .blue : .primary)
                
                Text(formatTime(segment.startTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(12)
            .background(isActive ? Color.blue.opacity(0.12) : Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .id(segment.id)
        .contextMenu {
            Button(action: {
                onEditRequest()
            }) {
                Label("Редактировать текст", systemImage: "pencil")
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
