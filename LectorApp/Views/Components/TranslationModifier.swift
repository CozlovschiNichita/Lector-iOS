import Foundation
import SwiftUI
import Combine
import NaturalLanguage
import Translation

// MARK: - Модификатор для перехвата перевода (iOS 18+)
@available(iOS 18.0, *)
struct TranslationExportModifier: ViewModifier {
    let fullText: String
    @Binding var targetLanguage: Locale.Language?
    let onComplete: (String) -> Void
    
    @State private var config: TranslationSession.Configuration?
    
    func body(content: Content) -> some View {
        content
            // Следим за выбором языка в меню
            .onChange(of: targetLanguage) { _, lang in
                if let lang = lang {
                    config = .init(target: lang)
                } else {
                    config = nil
                }
            }
            // Вызываем нативный интерфейс перевода Apple
            .translationTask(config) { session in
                do {
                    // Переводим только основной текст лекции
                    let result = try await session.translate(fullText)
                    await MainActor.run {
                        onComplete(result.targetText)
                        targetLanguage = nil
                    }
                } catch {
                    print("Ошибка перевода: \(error.localizedDescription)")
                    await MainActor.run { targetLanguage = nil }
                }
            }
    }
}

// MARK: Расширение для View
extension View {
    @ViewBuilder
    func withTranslation(fullText: String, targetLanguage: Binding<Locale.Language?>, onComplete: @escaping (String) -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.modifier(TranslationExportModifier(fullText: fullText, targetLanguage: targetLanguage, onComplete: onComplete))
        } else {
            self // На старых версиях iOS просто возвращаем View без модификатора
        }
    }
}
