import SwiftUI
import SwiftData

struct ProcessingQueueSheet: View {
    var processingLectures: [LocalLecture]
    @Binding var showProcessingQueue: Bool
    @Binding var lectureToCancel: LocalLecture?
    @Binding var showCancelProcessingAlert: Bool
    
    var body: some View {
        NavigationView {
            List {
                ForEach(processingLectures) { lecture in
                    NavigationLink(destination: LectureDetailView(lecture: mapToDTO(lecture), isModal: true)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lecture.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text(statusText(for: lecture))
                                    .font(.caption)
                                    .foregroundColor(lecture.status == "waiting_for_network" ? .orange : .secondary)
                            }
                            
                            Spacer()
                            
                            if lecture.status != "waiting_for_network" {
                                ZStack {
                                    Circle()
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 3)
                                    
                                    Circle()
                                        .trim(from: 0, to: CGFloat(lecture.progress ?? 0))
                                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear, value: lecture.progress)
                                    
                                    Text("\(Int((lecture.progress ?? 0) * 100))%")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                }
                                .frame(width: 44, height: 44)
                            }
                            
                            // Кнопка отмены
                            Button(action: {
                                lectureToCancel = lecture
                                showCancelProcessingAlert = true
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.8))
                                    .font(.title3)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(String(localized: "Очередь обработки"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(String(localized: "Свернуть")) { showProcessingQueue = false }
                        .fontWeight(.bold)
                }
            }
        }
    }
    
    // MARK: - Улучшенная логика статусов с локализацией
    private func statusText(for lecture: LocalLecture) -> String {
        switch lecture.status {
        case "waiting_for_network":
            return String(localized: "Ожидание интернета...")
        case "uploading":
            return String(localized: "Загрузка файла на сервер...")
        case "waiting_in_queue":
            return String(localized: "В очереди на расшифровку...")
        case "processing":
            return String(localized: "ИИ расшифровывает аудио...")
        default:
            return String(localized: "Обработка...")
        }
    }
    
    private func mapToDTO(_ local: LocalLecture) -> LectureDTO {
        return LectureDTO(
            id: local.id,
            title: local.title,
            fullText: local.fullText,
            summary: local.summary,
            summaryHistory: local.getSummaryHistory(),
            folderID: local.folderID,
            createdAt: local.createdAt,
            status: local.status,
            progress: local.progress,
            segments: local.getSegments()
        )
    }
}
