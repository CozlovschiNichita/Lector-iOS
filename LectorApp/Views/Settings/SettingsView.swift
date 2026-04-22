import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("aiLanguage") private var aiLanguage: String = "en"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("biometricTimeout") private var biometricTimeout: Double = 0
    
    @State private var showAboutApp = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                List {
                    Section(
                        header: Text("Языки"),
                        footer: Text("Язык интерфейса меняется в настройках iOS. Язык ИИ используется для распознавания речи и генерации конспектов.")
                    ) {
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Язык интерфейса")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Picker(selection: $aiLanguage, label: HStack {
                            Text("Язык ИИ (Распознавание)")
                        }) {
                            Text("English").tag("en")
                            Text("Русский").tag("ru")
                            Text("Română").tag("ro")
                            Text("Français").tag("fr")
                        }
                        .pickerStyle(.navigationLink)
                    }
                    
                    Section(header: Text("Оформление")) {
                        Picker("Тема приложения", selection: $appTheme) {
                            Text("Системная").tag("system")
                            Text("Светлая").tag("light")
                            Text("Темная").tag("dark")
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    Section(
                        header: Text("Безопасность"),
                        footer: Text("Настройте, через какое время приложение заблокируется после сворачивания.")
                    ) {
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Text("Разрешения (Face ID / Биометрия)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "faceid")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        NavigationLink(destination: BiometricTimeoutView(timeout: $biometricTimeout)) {
                            HStack {
                                Label("Запрос Face ID", systemImage: "lock.shield")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(timeoutLabel(biometricTimeout))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section(header: Text("О нас и связь")) {
                        Link(destination: URL(string: "mailto:www.LectorApp@hotmail.com")!) {
                            Label("Написать разработчику", systemImage: "envelope.fill")
                                .foregroundColor(.primary)
                        }
                        Link(destination: URL(string: "https://github.com/CozlovschiNichita")!) {
                            Label("Мы на GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.primary)
                        }
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID?action=write-review") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Label("Оценить приложение", systemImage: "star.fill")
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Section(header: Text("Помощь")) {
                        NavigationLink(destination: FAQDetailView()) {
                            Label("Вопросы и ответы (FAQ)", systemImage: "questionmark.circle.fill")
                        }
                        Button(action: { showAboutApp = true }) {
                            Label("О приложении", systemImage: "info.circle.fill")
                                .foregroundColor(.primary)
                        }
                    }

                    Section(header: Text("Аккаунт")) {
                        Button(action: {
                            AuthManager.shared.logout()
                            dismiss()
                        }) {
                            HStack {
                                Text("Выйти из аккаунта")
                                    .foregroundColor(.red)
                                Spacer()
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .navigationTitle("Настройки")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Закрыть") { dismiss() }
                    }
                }
                .sheet(isPresented: $showAboutApp) {
                    AboutAppSheet(showDeleteConfirmation: $showDeleteConfirmation)
                }
                .alert("Удалить аккаунт навсегда?", isPresented: $showDeleteConfirmation) {
                    Button("Отмена", role: .cancel) { }
                    Button("Удалить всё", role: .destructive) {
                        performFullAccountDeletion()
                    }
                } message: {
                    Text("Это действие безвозвратно удалит ваш профиль, все лекции, конспекты и аудиофайлы как на сервере, так и на этом устройстве. Восстановить данные будет невозможно.")
                }
                .alert("Ошибка удаления", isPresented: .constant(errorMessage != nil)) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    if let errorMsg = errorMessage { Text(errorMsg) }
                }
                
                if isDeleting {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5).tint(.white)
                        Text("Удаление данных...").foregroundColor(.white).font(.headline)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }
            }
        }
    }
    
    private func performFullAccountDeletion() {
        isDeleting = true
        Task {
            do {
                // Удаляем аккаунт на сервере
                try await AuthService().deleteAccount()
                
                await MainActor.run {
                    // Стираем локальные данные с устройства
                    AuthManager.shared.wipeAllLocalData(modelContext: modelContext)
                    
                    // Выходим из аккаунта (очищаем токены и перекидываем на логин)
                    AuthManager.shared.logout()
                    isDeleting = false
                    dismiss()
                }
            } catch let authError as AuthError {
                await MainActor.run {
                    isDeleting = false
                    switch authError {
                    case .serverError(let msg): errorMessage = msg
                    default: errorMessage = "Не удалось удалить аккаунт. Проверьте подключение к сети."
                    }
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Неизвестная ошибка."
                }
            }
        }
    }
    
    private func timeoutLabel(_ val: Double) -> String {
        switch val {
        case -1: return "Никогда"
        case 0: return "Сразу"
        case 60: return "Через 1 мин"
        case 300: return "Через 5 мин"
        case 3600: return "Через 1 час"
        case 86400: return "Через 1 день"
        default: return ""
        }
    }
}

// MARK: - ЭКРАН ВЫБОРА ТАЙМАУТА
struct BiometricTimeoutView: View {
    @Binding var timeout: Double
    
    let options: [(String, Double)] = [
        (String(localized: "Сразу"), 0),
        (String(localized: "Через 1 минуту"), 60),
        (String(localized: "Через 5 минут"), 300),
        (String(localized: "Через 1 час"), 3600),
        (String(localized: "Через 1 день"), 86400),
        (String(localized: "Никогда (Выключить)"), -1)
    ]
    
    var body: some View {
        List {
            ForEach(options, id: \.1) { option in
                Button(action: {
                    timeout = option.1
                }) {
                    HStack {
                        Text(option.0)
                            .foregroundColor(.primary)
                        Spacer()
                        if timeout == option.1 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Запрос Face ID")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Вспомогательное окно "О приложении"
struct AboutAppSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var showDeleteConfirmation: Bool
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)
                    
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 5)
                    
                    VStack(spacing: 8) {
                        Text("Lector").font(.system(size: 32, weight: .bold))
                        Text("Версия 1.0.0").foregroundColor(.secondary).font(.subheadline)
                    }
                    
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Lector — это не просто диктофон. Это ваш интеллектуальный мост между живым словом преподавателя и структурированными знаниями в вашем кармане.")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("Мы создали это приложение, чтобы освободить вас от рутинного переписывания лекций. Наша миссия — позволить вам сфокусироваться на самом процессе обучения и понимании материала, пока технологии берут на себя механическую работу.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        
                        Text("В основе Lector лежат передовые нейросетевые модели семейства Whisper. Они способны с поразительной точностью распознавать человеческую речь, структурировать её по смыслам и выделять ключевые тезисы, превращая часы аудиозаписей в лаконичные и понятные конспекты.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        
                        Text("Ваши данные — это ваша собственность. Мы верим в абсолютную конфиденциальность, поэтому все аудиофайлы обрабатываются в защищенной среде и не хранятся на наших серверах после завершения транскрипции. Учитесь эффективно, зная, что ваши знания всегда под рукой и в полной безопасности.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 25)
                    .multilineTextAlignment(.leading)
                    
                    // Гибкий отступ вместо жестких 40 поинтов
                    Spacer()
                    
                    // НОВАЯ МИНИМАЛИСТИЧНАЯ КНОПКА (Apple Style)
                    Button(action: {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showDeleteConfirmation = true
                        }
                    }) {
                        Text("Удалить учетную запись")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.red)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }.font(.headline)
                }
            }
        }
    }
}

// MARK: - FAQ
struct FAQDetailView: View {
    var body: some View {
        List {
            Section(header: Text("Организация и Папки")) {
                FAQItem(
                    question: "Как переместить лекции в папку?",
                    answer: "Перейдите в историю лекций, нажмите кнопку выбора в правом верхнем углу, выделите нужные записи и нажмите 'В папку' на нижней панели. Также вы можете смахнуть нужную лекцию влево или удерживать на ней палец."
                )
                FAQItem(
                    question: "Что дает закрепление (Pin)?",
                    answer: "Закрепленные папки и лекции всегда будут отображаться в самом верху вашего списка для быстрого доступа. Чтобы закрепить элемент, смахните его вправо или воспользуйтесь долгим нажатием."
                )
                FAQItem(
                    question: "Как удалить несколько элементов сразу?",
                    answer: "Включите режим редактирования с помощью кнопки выбора сверху, отметьте ненужные лекции или папки и нажмите кнопку удаления в появившейся внизу капсуле."
                )
            }
            
            Section(header: Text("Офлайн-режим и сеть")) {
                FAQItem(
                    question: "Можно ли записывать лекции без интернета?",
                    answer: "Да, вы можете начать запись даже без доступа к сети. Аудио сохранится локально на вашем устройстве. Как только интернет появится, лекция получит статус «Ожидание сети»."
                )
                FAQItem(
                    question: "Что значит статус «Ожидание сети»?",
                    answer: "Это означает, что лекция записана и сохранена на iPhone, но еще не отправлена на сервер для расшифровки. Просто откройте приложение при наличии интернета, и загрузка начнется автоматически."
                )
                FAQItem(
                    question: "Нужен ли интернет для чтения уже готовых лекций?",
                    answer: "Тексты и конспекты синхронизируются с сервером. После того как лекция была один раз загружена, она кэшируется и будет доступна для чтения даже офлайн."
                )
                FAQItem(
                    question: "Синхронизируются ли папки между устройствами?",
                    answer: "Да, если вы авторизованы в своем аккаунте и устройство подключено к интернету, все ваши папки, лекции и конспекты автоматически сохраняются в облаке."
                )
            }
            
            Section(header: Text("Лимиты и файлы")) {
                FAQItem(
                    question: "Какие ограничения на длительность записи?",
                    answer: "Максимальное время одной записи составляет 2 часа. Это сделано для обеспечения стабильности обработки аудио нейросетью и экономии заряда аккумулятора."
                )
                FAQItem(
                    question: "Почему мой файл не загружается?",
                    answer: "Убедитесь, что формат файла — MP3, M4A, WAV, MP4 или MOV, а размер не превышает 1.5 ГБ. Другие типы файлов не поддерживаются."
                )
                FAQItem(
                    question: "Проблема с импортом из YouTube?",
                    answer: "Импорт может не работать, если видео длится более 2 часов, защищено авторскими правами (музыкальные клипы) или имеет ограниченный доступ (приватные видео)."
                )
            }
            
            Section(header: Text("Конфиденциальность и Технологии")) {
                FAQItem(
                    question: "Где хранятся мои аудиозаписи?",
                    answer: "Ваши аудиозаписи хранятся исключительно в памяти вашего устройства. Мы не храним копии аудио на сервере после завершения процесса транскрипции."
                )
                FAQItem(
                    question: "Как работает распознавание текста?",
                    answer: "Для точной расшифровки вашей речи мы используем передовую нейросетевую модель (Whisper), которая обрабатывает аудио на нашем выделенном сервере."
                )
            }
        }
        .navigationTitle("FAQ")
        .listStyle(.insetGrouped)
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.vertical, 5)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(question)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
