import SwiftUI

struct Shake: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)), y: 0))
    }
}

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    
    @State private var isRegisterMode = false
    @State private var shakeCount: CGFloat = 0
    @State private var showForgotPassword = false
    @State private var isPasswordVisible = false
    
    @AppStorage("appTheme") private var appTheme: String = "system"
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Заголовок
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            // Локализация в тернарном операторе
                            Text(isRegisterMode ? String(localized: "Создать аккаунт") : String(localized: "С возвращением"))
                                .font(.system(size: 32, weight: .bold))
                                .id(isRegisterMode)
                            
                            Text(isRegisterMode ? String(localized: "Начните записывать лекции умнее") : String(localized: "Авторизуйтесь для доступа к записям"))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .id(isRegisterMode)
                        }
                        Spacer()
                    }
                    .padding(.top, 60)
                    .padding(.bottom, 10)
                    
                    // Блок ввода данных
                    VStack(spacing: 16) {
                        if isRegisterMode {
                            HStack {
                                inputField(icon: "person.fill", placeholder: "Имя", text: $viewModel.firstName)
                                inputField(icon: "person.fill", placeholder: "Фамилия", text: $viewModel.lastName)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        inputField(icon: "envelope.fill", placeholder: "Email", text: $viewModel.email, keyboardType: .emailAddress)
                        passwordField()
                        
                        if isRegisterMode {
                            passwordRequirementsView
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .modifier(Shake(animatableData: shakeCount))
                    
                    if !isRegisterMode {
                        // Автоматически локализуется как литерал
                        Button("Забыли пароль?") {
                            showForgotPassword = true
                        }
                        .font(.footnote.bold())
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, -5)
                    }
                    
                    if !viewModel.errorMessage.isEmpty {
                        // Сообщение об ошибке должно приходить уже локализованным из ViewModel
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    
                    // Основная кнопка действия
                    Button(action: performAuth) {
                        if viewModel.isLoading {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                        } else {
                            Text(isRegisterMode ? String(localized: "Зарегистрироваться") : String(localized: "Войти"))
                                .font(.headline).frame(maxWidth: .infinity)
                                .id(isRegisterMode)
                        }
                    }
                    .padding()
                    .background(networkMonitor.isConnected ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .shadow(color: Color.blue.opacity(0.3), radius: 10, y: 5)
                    .padding(.top, 5)
                    .disabled(viewModel.isLoading || !networkMonitor.isConnected)
                    
                    HStack {
                        VStack { Divider() }
                        Text("ИЛИ").font(.caption).foregroundColor(.gray)
                        VStack { Divider() }
                    }
                    .padding(.vertical, 2)
                    
                    Button(action: {
                        Task { await viewModel.signInWithGoogle() }
                    }) {
                        HStack(spacing: 12) {
                            Image("google_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            Text("Продолжить с Google")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(UIColor.separator), lineWidth: 1)
                        )
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(14)
                    }
                    .disabled(viewModel.isLoading || !networkMonitor.isConnected)
                    
                    Spacer(minLength: 40)
                    
                    // Переключатель режимов в самом низу
                    Button(action: {
                        hideKeyboard()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isRegisterMode.toggle()
                            viewModel.errorMessage = ""
                            viewModel.password = ""
                        }
                    }) {
                        Text(isRegisterMode ? String(localized: "Уже есть аккаунт? Войти") : String(localized: "Нет аккаунта? Зарегистрироваться"))
                            .font(.footnote.bold())
                            .foregroundColor(.blue)
                            .id(isRegisterMode)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            
            // Настройки внешнего вида (Кнопка глобуса)
            HStack {
                Spacer()
                Menu {
                    Section("Внешний вид") {
                        Picker(selection: $appTheme, label: Label("Тема", systemImage: "paintpalette")) {
                            Text("Системная").tag("system")
                            Text("Светлая").tag("light")
                            Text("Тёмная").tag("dark")
                        }
                    }
                    
                    Section("Язык приложения") {
                        Button(action: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            let currentLang = Bundle.main.preferredLocalizations.first?.uppercased() ?? ""
                            Label("Настройки (Текущий: \(currentLang))", systemImage: "character.bubble")
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.top, 10)
            }
            .zIndex(2)

            // Индикатор отсутствия сети
            if !networkMonitor.isConnected {
                VStack {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Нет подключения к интернету")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.red)
                    .shadow(radius: 5)
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut, value: networkMonitor.isConnected)
                .zIndex(3)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    // ВАЖНО: Заменил тип placeholder на LocalizedStringKey
    private func inputField(icon: String, placeholder: LocalizedStringKey, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray).frame(width: 24)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func passwordField() -> some View {
        HStack {
            Image(systemName: "lock.fill").foregroundColor(.gray).frame(width: 24)
            
            ZStack(alignment: .leading) {
                if isPasswordVisible {
                    TextField("Пароль", text: $viewModel.password)
                } else {
                    SecureField("Пароль", text: $viewModel.password)
                }
            }
            .autocapitalization(.none)
            .disableAutocorrection(true)
            
            Button(action: {
                withAnimation(.snappy(duration: 0.2)) { isPasswordVisible.toggle() }
            }) {
                Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.gray)
                    .frame(width: 24, height: 24)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var passwordRequirementsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirementRow(text: "Минимум 6 символов", isMet: viewModel.hasMinLength)
            requirementRow(text: "Хотя бы одна заглавная буква", isMet: viewModel.hasUppercase)
            requirementRow(text: "Хотя бы одна цифра", isMet: viewModel.hasDigit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
    
    // ВАЖНО: Заменил тип text на LocalizedStringKey
    private func requirementRow(text: LocalizedStringKey, isMet: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray).font(.caption)
            Text(text).font(.caption).foregroundColor(isMet ? .green : .gray)
        }
    }
    
    private func performAuth() {
        hideKeyboard()
        Task {
            if isRegisterMode { await viewModel.register() } else { await viewModel.login() }
            if !viewModel.errorMessage.isEmpty {
                withAnimation(.default) { shakeCount += 1 }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
}
