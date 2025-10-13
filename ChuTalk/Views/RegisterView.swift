//
//  RegisterView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = AuthService.shared

    @State private var username = ""
    @State private var displayName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var showPassword = false
    @State private var showConfirmPassword = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("アカウント作成")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)

                VStack(spacing: 16) {
                    TextField("ユーザーID", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("表示名", text: $displayName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        if showPassword {
                            TextField("パスワード", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("パスワード", text: $password)
                        }

                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    HStack {
                        if showConfirmPassword {
                            TextField("パスワード確認", text: $confirmPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        } else {
                            SecureField("パスワード確認", text: $confirmPassword)
                        }

                        Button(action: { showConfirmPassword.toggle() }) {
                            Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Validation hints
                    if !password.isEmpty && password.count < 6 {
                        Text("パスワードは6文字以上にしてください")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if !password.isEmpty && !confirmPassword.isEmpty && password != confirmPassword {
                        Text("パスワードが一致しません")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }

                    Button(action: register) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("登録")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(Constants.UI.cornerRadius)
                    .disabled(isLoading || !isValidForm)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarItems(leading: Button("キャンセル") {
                dismiss()
            })
            .alert("登録完了", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("アカウントが作成されました。\n\nユーザーID: \(username)\n\n登録したパスワードでログインしてください。")
            }
        }
    }

    private var isValidForm: Bool {
        !username.isEmpty &&
        !displayName.isEmpty &&
        !password.isEmpty &&
        password == confirmPassword &&
        password.count >= 6
    }

    private func register() {
        errorMessage = nil
        isLoading = true

        print("🔵 RegisterView: Starting registration...")
        print("   Username: \(username)")
        print("   Display Name: \(displayName)")
        print("   Password length: \(password.count)")

        Task {
            do {
                try await authService.register(
                    username: username,
                    password: password,
                    displayName: displayName
                )

                print("✅ RegisterView: Registration successful")

                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                    print("✅ RegisterView: Showing success alert")
                }
            } catch {
                print("❌ RegisterView: Registration failed - \(error)")
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    print("❌ RegisterView: Error message set: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    RegisterView()
}
