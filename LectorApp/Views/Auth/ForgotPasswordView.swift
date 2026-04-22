import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    private let authService = AuthService()
    
    @State private var email = ""
    @State private var code = ""
    @State private var newPassword = "" // Без фильтров
    
    @State private var isCodeSent = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var isPasswordVisible = false
    
    // MARK: - Валидация
    var hasMinLength: Bool { newPassword.count >= 6 }
    var hasUppercase: Bool { newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil }
    var hasDigit: Bool { newPassword.rangeOfCharacter(from: .decimalDigits) != nil }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 25) {
                
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Нет подключения к интернету")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.red)
                    .cornerRadius(8)
                }
                
                Image(systemName: isCodeSent ? "lock.rotation" : "envelope.badge.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.top, 20)
                
                Text(isCodeSent ? "Введите код" : "Восстановление пароля")
                    .font(.title2.bold())
                
                if !isCodeSent {
                    Text("Введите email, указанный при регистрации. Мы отправим на него 6-значный код для сброса.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    inputField(icon: "envelope.fill", placeholder: "Email", text: $email, keyboardType: .emailAddress)
                } else {
                    Text("Код отправлен на \(email)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    inputField(icon: "number", placeholder: "6-значный код", text: $code, keyboardType: .numberPad)
                    
                    passwordField()
                    
                    passwordRequirementsView
                        .padding(.top, 5)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundColor(.red).font(.caption)
                }
                if !successMessage.isEmpty {
                    Text(successMessage).foregroundColor(.green).font(.caption)
                }
                
                Button(action: {
                    Task { isCodeSent ? await resetPassword() : await sendCode() }
                }) {
                    if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text(isCodeSent ? "Сохранить новый пароль" : "Отправить код")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(networkMonitor.isConnected ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color.blue.opacity(0.3), radius: 10, y: 5)
                .disabled(isLoading || !networkMonitor.isConnected)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - UI Components
    private func inputField(icon: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray).frame(width: 24)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .autocapitalization(.none)
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
                    TextField("Новый пароль", text: $newPassword)
                } else {
                    SecureField("Новый пароль", text: $newPassword)
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
            requirementRow(text: "Минимум 6 символов", isMet: hasMinLength)
            requirementRow(text: "Хотя бы одна заглавная буква", isMet: hasUppercase)
            requirementRow(text: "Хотя бы одна цифра", isMet: hasDigit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
    
    private func requirementRow(text: String, isMet: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isMet ? .green : .gray).font(.caption)
            Text(text).font(.caption).foregroundColor(isMet ? .green : .gray)
        }
    }
    
    // MARK: - Logic
    private func sendCode() async {
        guard !email.isEmpty else { errorMessage = "Введите email"; return }
        isLoading = true; errorMessage = ""
        do {
            try await authService.forgotPassword(email: email)
            isCodeSent = true
        } catch AuthError.serverError(let msg) { errorMessage = msg } catch { errorMessage = "Ошибка сервера" }
        isLoading = false
    }
    
    private func resetPassword() async {
        // Жесткая проверка по всем условиям
        guard !code.isEmpty, hasMinLength, hasUppercase, hasDigit else {
            errorMessage = "Пароль не соответствует требованиям безопасности"
            return
        }
        isLoading = true; errorMessage = ""
        do {
            try await authService.resetPassword(email: email, code: code, newPassword: newPassword)
            successMessage = "Пароль успешно изменен!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        } catch AuthError.serverError(let msg) { errorMessage = msg } catch { errorMessage = "Ошибка сервера" }
        isLoading = false
    }
}
