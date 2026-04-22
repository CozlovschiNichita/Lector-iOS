import SwiftUI
import Combine

// MARK: - Отслеживание клавиатуры (Переиспользуемый класс)
final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var animationDuration: Double = 0.25
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        let willShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        
        willShow.merge(with: willChange)
            .sink { [weak self] notification in
                guard let self = self else { return }
                
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                   let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                    self.height = frame.height
                    self.animationDuration = duration
                }
            }
            .store(in: &cancellables)
        
        willHide
            .sink { [weak self] _ in
                self?.height = 0
            }
            .store(in: &cancellables)
    }
}

// MARK: - Единый контейнер для нижнего UI
struct BottomOverlayContainer<Content: View>: View {
    @ObservedObject var keyboard: KeyboardObserver
    let isMiniPlayerVisible: Bool
    
    var miniPlayerPadding: CGFloat = 100
    var defaultPadding: CGFloat = 20
    
    let content: Content
    
    init(keyboard: KeyboardObserver, isMiniPlayerVisible: Bool, miniPlayerPadding: CGFloat = 100, defaultPadding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.keyboard = keyboard
        self.isMiniPlayerVisible = isMiniPlayerVisible
        self.miniPlayerPadding = miniPlayerPadding
        self.defaultPadding = defaultPadding
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal)
        .padding(.bottom, keyboard.height > 0 ? 5 : (isMiniPlayerVisible ? miniPlayerPadding : defaultPadding))
    }
}
