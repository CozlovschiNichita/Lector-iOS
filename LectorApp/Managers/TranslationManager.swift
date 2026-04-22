import Foundation
import SwiftUI
import Combine
import NaturalLanguage
import Translation

// MARK: - Помощник для работы с языками и их проверкой
class TranslationHelper: ObservableObject {
    @Published var supportedLanguages: [Locale.Language] = []
    @Published var isRomanian = false
    
    // Проверка на румынский язык
    func checkRomanian(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        DispatchQueue.main.async {
            self.isRomanian = recognizer.dominantLanguage == .romanian
        }
    }
    
    // Загрузка всех поддерживаемых системой языков (iOS 18+)
    @available(iOS 18.0, *)
    func fetchSupportedLanguages() async {
        let availability = LanguageAvailability()
        let langs = await availability.supportedLanguages
        DispatchQueue.main.async {
            self.supportedLanguages = langs
                .filter { $0.minimalIdentifier != "ro" }
                .sorted { self.localizedName(for: $0) < self.localizedName(for: $1) }
        }
    }
    
    func localizedName(for lang: Locale.Language) -> String {
        // Используем minimalIdentifier
        let id = lang.minimalIdentifier
        return Locale.current.localizedString(forIdentifier: id) ?? id
    }
}
