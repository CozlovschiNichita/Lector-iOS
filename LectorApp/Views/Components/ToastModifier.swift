import SwiftUI

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isShowing {
                VStack {
                    Spacer()
                    
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color(UIColor.darkGray).opacity(0.95))
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                        .padding(.bottom, 130)
                }
                .zIndex(100)
            }
        }
        .task(id: isShowing) {
            guard isShowing else { return }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            if !Task.isCancelled {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isShowing = false
                }
            }
        }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String) -> some View {
        self.modifier(ToastModifier(isShowing: isShowing, message: message))
    }
}
