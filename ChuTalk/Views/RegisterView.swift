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

    // オレンジをモチーフにしたカラーパレット
    private let primaryOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    private let accentOrange = Color(red: 0.95, green: 0.5, blue: 0.1)
    private let backgroundGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.95, blue: 0.9), Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationView {
            ZStack {
                // 背景グラデーション
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 32) {
                        // ヘッダー
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [primaryOrange, accentOrange],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                    .shadow(color: primaryOrange.opacity(0.3), radius: 15, x: 0, y: 8)

                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 36))
                                    .foregroundColor(.white)
                            }

                            Text("新規アカウント作成")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [primaryOrange, accentOrange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )

                            Text("ChuTalkで繋がろう")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 40)

                        // 入力フォーム
                        VStack(spacing: 20) {
                            // ユーザーID
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ユーザーID")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentOrange)

                                HStack(spacing: 12) {
                                    Image(systemName: "at")
                                        .foregroundColor(primaryOrange)
                                        .frame(width: 20)

                                    TextField("例: yamada", text: $username)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)

                                Text("ログイン時に使用するIDです")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                            }

                            // 表示名
                            VStack(alignment: .leading, spacing: 8) {
                                Text("表示名")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentOrange)

                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .foregroundColor(primaryOrange)
                                        .frame(width: 20)

                                    TextField("例: 山田太郎", text: $displayName)
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)

                                Text("他のユーザーに表示される名前です")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.leading, 4)
                            }

                            // パスワード
                            VStack(alignment: .leading, spacing: 8) {
                                Text("パスワード")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentOrange)

                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(primaryOrange)
                                        .frame(width: 20)

                                    if showPassword {
                                        TextField("6文字以上", text: $password)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    } else {
                                        SecureField("6文字以上", text: $password)
                                    }

                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.gray.opacity(0.6))
                                    }
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)

                                // パスワード強度インジケーター
                                if !password.isEmpty {
                                    HStack(spacing: 8) {
                                        if password.count >= 6 {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("パスワードの長さOK")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.orange)
                                            Text("6文字以上入力してください")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    .padding(.leading, 4)
                                }
                            }

                            // パスワード確認
                            VStack(alignment: .leading, spacing: 8) {
                                Text("パスワード確認")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(accentOrange)

                                HStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .foregroundColor(primaryOrange)
                                        .frame(width: 20)

                                    if showConfirmPassword {
                                        TextField("もう一度入力", text: $confirmPassword)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    } else {
                                        SecureField("もう一度入力", text: $confirmPassword)
                                    }

                                    Button(action: { showConfirmPassword.toggle() }) {
                                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.gray.opacity(0.6))
                                    }
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)

                                // パスワード一致確認
                                if !confirmPassword.isEmpty {
                                    HStack(spacing: 8) {
                                        if password == confirmPassword {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("パスワードが一致しています")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                            Text("パスワードが一致しません")
                                                .font(.caption)
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.leading, 4)
                                }
                            }

                            // エラーメッセージ
                            if let errorMessage = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.system(size: 13))
                                        .foregroundColor(.red)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                            }

                            // 登録ボタン
                            Button(action: register) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                        Text("アカウントを作成")
                                            .font(.system(size: 18, weight: .bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: [primaryOrange, accentOrange],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: primaryOrange.opacity(0.4), radius: 10, x: 0, y: 5)
                            }
                            .disabled(isLoading || !isValidForm)
                            .opacity((isLoading || !isValidForm) ? 0.6 : 1.0)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("戻る")
                        }
                        .foregroundColor(primaryOrange)
                    }
                }
            }
            .alert("登録完了", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("アカウントが作成されました。\n\nユーザーID: \(username)\n\n登録したパスワードでログインしてください。")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPadでもスタックスタイルを使用
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
        print("   Password (DEBUG): \(password)")  // デバッグ用
        FileLogger.shared.log("Registration attempt - username: \(username), password length: \(password.count), password: \(password)", category: "RegisterView")

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
