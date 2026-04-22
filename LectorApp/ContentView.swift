import SwiftUI
import SwiftData

struct ContentView: View {
    @ObservedObject private var authManager = AuthManager.shared
    
    @State private var showDetailFromPlayer = false
    @State private var selectedTab = 1

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                // Экран входа
                LoginView()
            } else {
                ZStack {
                    // Основной контент приложения
                    ZStack(alignment: .bottom) {
                        TabView(selection: $selectedTab) {
                            NavigationView {
                                HistoryView(folder: nil)
                            }
                            .tabItem { Label("Все лекции", systemImage: "tray.full.fill") }
                            .tag(0)
                            
                            RecordingView(selectedTab: $selectedTab)
                                .tabItem { Label("Запись", systemImage: "mic.fill") }
                                .tag(1)
                            
                            FoldersView(selectedTab: $selectedTab)
                                .tabItem { Label("Папки", systemImage: "folder.fill") }
                                .tag(2)
                        }
                        
                        MiniPlayerOverlay(showDetail: $showDetailFromPlayer)
                    }
                    // Размываем фон, если приложение заблокировано
                    .blur(radius: authManager.isUnlocked ? 0 : 20)
                    .allowsHitTesting(authManager.isUnlocked)
                    
                    // Экран Face ID поверх всего
                    if !authManager.isUnlocked {
                        LockedView()
                            .transition(.opacity)
                    }
                }
                .sheet(isPresented: $showDetailFromPlayer) {
                    if let lecture = GlobalAudioPlayer.shared.playingLecture {
                        NavigationView {
                            LectureDetailView(lecture: lecture, isModal: true)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserDidLogout"))) { _ in
            GlobalAudioPlayer.shared.close()
        }
    }
}

// MARK: - Экран блокировки
struct LockedView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).opacity(0.7).ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                
                Text("Lector заблокирован")
                    .font(.title2).bold()
                
                Text("Используйте биометрию для доступа к вашим записям и конспектам.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()
                
                Button(action: {
                    AuthManager.shared.authenticateWithBiometrics()
                }) {
                    Label("Разблокировать", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 30)
                
                Button("Выйти из аккаунта") {
                    AuthManager.shared.logout()
                }
                .font(.footnote).foregroundColor(.red).padding(.bottom, 40)
            }
        }
        .onAppear {
            AuthManager.shared.authenticateWithBiometrics()
        }
    }
}

// MARK: - Мини-плеер 
struct MiniPlayerOverlay: View {
    @ObservedObject var player = GlobalAudioPlayer.shared
    @Binding var showDetail: Bool
    
    var body: some View {
        if player.playingLecture != nil {
            MiniPlayerView()
                .padding(.bottom, 54)
                .onTapGesture { showDetail = true }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
