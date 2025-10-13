//
//  LoginView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct LoginView: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRegister = false
    @State private var showPassword = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                // Logo
                Image(systemName: "video.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("ChuTalk")
                    .font(.system(size: 36, weight: .bold))

                Spacer()

                // Login Form
                VStack(spacing: 16) {
                    TextField("ユーザーID", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

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

                    if let errorMessage = errorMessage {
                        VStack(spacing: 8) {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)

                            if errorMessage.contains("unauthorized") || errorMessage.contains("invalid") {
                                Text("ヒント：\n• ユーザーIDとパスワードを確認してください\n• 目のアイコンをタップしてパスワードを確認できます\n• 登録時と同じ情報を入力してください")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.leading)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("ログイン")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(Constants.UI.cornerRadius)
                    .disabled(isLoading || username.isEmpty || password.isEmpty)

                    Button(action: { showRegister = true }) {
                        Text("アカウントをお持ちでない方")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
        }
    }

    private func login() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await authService.login(username: username, password: password)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    LoginView()
}
