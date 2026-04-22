import SwiftUI

struct ControlPanel: View {
    var timeElapsed: TimeInterval
    @ObservedObject var viewModel: RecordingViewModel
    @ObservedObject var importService: ImportService
    @ObservedObject var globalPlayer: GlobalAudioPlayer
    
    var isExtractingAudio: Bool
    var processingLecturesCount: Int
    var isProcessingTail: Bool
    
    var onTrash: () -> Void
    var onPlus: () -> Void
    var onToggleRecord: () -> Void
    var onSave: () -> Void
    
    var body: some View {
        HStack(alignment: .center) { // Центрируем по вертикали
            // левая кнопка
            Group {
                if timeElapsed > 0 {
                    Button(action: onTrash) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 56, height: 56)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                } else {
                    Spacer().frame(width: 56)
                }
            }
            .frame(width: 80)
            
            Spacer()
            
            // центральная кнопка (ЗАПИСЬ)
            Button(action: onToggleRecord) {
                ZStack {
                    if viewModel.isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 90, height: 90)
                            .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: viewModel.isRecording)
                    }
                    
                    Circle()
                        .fill(viewModel.isRecording ? .red : .blue)
                        .frame(width: 72, height: 72)
                        .shadow(color: (viewModel.isRecording ? Color.red : Color.blue).opacity(0.3), radius: 10)
                    
                    Image(systemName: viewModel.isRecording ? "pause.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 110, height: 110)
            
            Spacer()
            
            // правая кнопка
            Group {
                if timeElapsed > 0 {
                    Button(action: onSave) {
                        ZStack {
                            if isProcessingTail || viewModel.isFinalizing {
                                ProgressView().tint(.green)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Circle())
                    }
                    .disabled(isProcessingTail || viewModel.isFinalizing)
                } else {
                    Button(action: onPlus) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.blue)
                            .frame(width: 56, height: 56)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .disabled(isExtractingAudio)
                }
            }
            .frame(width: 80)
        }
        .padding(.horizontal, 30)
        .frame(height: 110)
    }
}
