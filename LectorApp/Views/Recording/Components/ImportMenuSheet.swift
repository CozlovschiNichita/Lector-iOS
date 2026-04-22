import SwiftUI
import PhotosUI

struct ImportMenuSheet: View {
    @Binding var aiLanguage: String
    @Binding var showPlusMenu: Bool
    @Binding var isFilePickerPresented: Bool
    @Binding var showOfflineAlert: Bool
    @Binding var showYouTubeAlert: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Язык ИИ
                    Menu {
                        Picker("Язык", selection: $aiLanguage) {
                            Text("English").tag("en")
                            Text("Русский").tag("ru")
                            Text("Română").tag("ro")
                            Text("Français").tag("fr")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "waveform.and.mic")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Язык: \(languageName(for: aiLanguage))")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                    }

                    // Кнопки импорта
                    VStack(spacing: 12) {
                        actionCard(icon: "doc.fill", color: .blue, title: "Файлы (Аудио / Видео)", subtitle: "До 1.5 ГБ • MP3, M4A, WAV, MP4, MOV") {
                            if networkMonitor.isConnected {
                                showPlusMenu = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isFilePickerPresented = true }
                            } else { showOfflineAlert = true }
                        }
                        
                        if networkMonitor.isConnected {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                                actionCardContent(icon: "photo.on.rectangle", color: .purple, title: "Галерея (Видео)", subtitle: "До 1.5 ГБ")
                            }
                            .buttonStyle(PlainButtonStyle())
                        } else {
                            Button(action: { showOfflineAlert = true }) {
                                actionCardContent(icon: "photo.on.rectangle", color: .purple, title: "Галерея (Видео)", subtitle: "До 1.5 ГБ")
                            }
                        }
                        
                        actionCard(icon: "play.rectangle.fill", color: .red, title: "YouTube", subtitle: "По ссылке (до 2 часов)") {
                            if networkMonitor.isConnected {
                                showPlusMenu = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showYouTubeAlert = true }
                            } else { showOfflineAlert = true }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Создать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { showPlusMenu = false }
                }
            }
        }
    }
    
    private func languageName(for code: String) -> String {
        switch code {
        case "en": return "English"
        case "ru": return "Русский"
        case "ro": return "Română"
        case "fr": return "Français"
        default: return code
        }
    }
    
    private func actionCard(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionCardContent(icon: icon, color: color, title: title, subtitle: subtitle)
        }
    }
    
    private func actionCardContent(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 50, height: 50)
                Image(systemName: icon).font(.title2).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundColor(.primary)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}
