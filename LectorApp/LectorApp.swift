import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct LectorApp: App {
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("biometricTimeout") private var biometricTimeout: Double = 0
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Инициализируем контейнер базы данных вручную
    let container: ModelContainer
    
    init() {
        do {
            container = try ModelContainer(for: LocalFolder.self, LocalLecture.self)
            
            // при запуске передаем управление базой данных менеджеру синхронизации
            SyncManager.shared.setContext(container.mainContext)
            
        } catch {
            fatalError("Не удалось инициализировать ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appTheme == "system" ? nil : (appTheme == "dark" ? .dark : .light))
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onAppear {
                    GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: "909923047688-l3ph8ob2ib3mb52oj2afrkqet4bsfk2a.apps.googleusercontent.com")
                }
        }
        // Обязательно передаем наш созданный контейнер
        .modelContainer(container)
        // Прокидываем единый монитор сети во всё приложение
        .environmentObject(SyncManager.shared.networkMonitor)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .inactive || newPhase == .background {
                UserDefaults.standard.set(Date(), forKey: "lastExitDate")
            } else if newPhase == .active {
                checkBiometricLock()
            }
        }
    }
    
    private func checkBiometricLock() {
        if biometricTimeout < 0 {
            AuthManager.shared.isUnlocked = true
            return
        }
        
        guard AuthManager.shared.isAuthenticated else { return }
        
        if let bgDate = UserDefaults.standard.object(forKey: "lastExitDate") as? Date {
            let timeAway = Date().timeIntervalSince(bgDate)
            
            if timeAway >= biometricTimeout {
                AuthManager.shared.isUnlocked = false
            } else {
                AuthManager.shared.isUnlocked = true
            }
            
            // Очищаем время после проверки
            UserDefaults.standard.removeObject(forKey: "lastExitDate")
        }
    }
}
