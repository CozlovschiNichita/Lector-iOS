import SwiftUI

struct OfflineIndicator: View {
    @EnvironmentObject private var network: NetworkMonitor
    
    var body: some View {
        if !network.isConnected {
            Menu {
                Text("Режим офлайн. Функции ИИ временно недоступны. Аудиозаписи будут обработаны позже.")
            } label: {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
                    .imageScale(.large)
            }
            .transition(.opacity)
            .animation(.easeInOut, value: network.isConnected)
        }
    }
}
