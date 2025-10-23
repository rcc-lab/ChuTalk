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
    @State private var agreedToTerms = false
    @State private var showTerms = false

    // オレンジをモチーフにしたカラーパレット
    private let primaryOrange = Color(red: 1.0, green: 0.6, blue: 0.2)  // 明るいオレンジ
    private let secondaryOrange = Color(red: 1.0, green: 0.75, blue: 0.4) // やさしいオレンジ
    private let accentOrange = Color(red: 0.95, green: 0.5, blue: 0.1)   // 濃いオレンジ
    private let backgroundGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.95, blue: 0.9), Color.white],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // 背景グラデーション
                    backgroundGradient
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer()
                                .frame(height: max(50, geometry.size.height * 0.1))

                            // ロゴエリア
                            VStack(spacing: 16) {
                                // オリジナルロゴ（手を繋いだデザイン）
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: isIPad ? 180 : 120, height: isIPad ? 180 : 120)
                                    .cornerRadius(isIPad ? 36 : 24)
                                    .shadow(color: primaryOrange.opacity(0.3), radius: 20, x: 0, y: 10)

                                // アプリ名とキャッチコピー
                                VStack(spacing: 8) {
                                    Text("ChuTalk")
                                        .font(.system(size: isIPad ? 56 : 42, weight: .bold, design: .rounded))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [primaryOrange, accentOrange],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )

                                    Text("中部特機で、トーク中。")
                                        .font(.system(size: isIPad ? 20 : 15, weight: .medium))
                                        .foregroundColor(accentOrange.opacity(0.8))
                                        .tracking(1)
                                }
                            }
                            .padding(.bottom, isIPad ? 80 : 50)

                            Spacer()
                                .frame(height: max(30, geometry.size.height * 0.05))

                            // ログインフォーム（中央配置、最大幅制限）
                            VStack(spacing: 18) {
                                // ユーザーID入力
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("ユーザーID")
                                        .font(.system(size: isIPad ? 18 : 14, weight: .semibold))
                                        .foregroundColor(accentOrange)

                                    HStack(spacing: 12) {
                                        Image(systemName: "person.fill")
                                            .foregroundColor(primaryOrange)
                                            .frame(width: 20)
                                            .font(.system(size: isIPad ? 20 : 16))

                                        TextField("例: yamada", text: $username)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            .font(.system(size: isIPad ? 18 : 16))
                                    }
                                    .padding(isIPad ? 20 : 16)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                }

                                // パスワード入力
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("パスワード")
                                        .font(.system(size: isIPad ? 18 : 14, weight: .semibold))
                                        .foregroundColor(accentOrange)

                                    HStack(spacing: 12) {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(primaryOrange)
                                            .frame(width: 20)
                                            .font(.system(size: isIPad ? 20 : 16))

                                        if showPassword {
                                            TextField("パスワードを入力", text: $password)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                                .font(.system(size: isIPad ? 18 : 16))
                                        } else {
                                            SecureField("パスワードを入力", text: $password)
                                                .font(.system(size: isIPad ? 18 : 16))
                                        }

                                        Button(action: { showPassword.toggle() }) {
                                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                                .foregroundColor(.gray.opacity(0.6))
                                                .font(.system(size: isIPad ? 20 : 16))
                                        }
                                    }
                                    .padding(isIPad ? 20 : 16)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                                }

                                // エラーメッセージ
                                if let errorMessage = errorMessage {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text(errorMessage)
                                            .font(.system(size: isIPad ? 16 : 13))
                                            .foregroundColor(.red)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(10)
                                }

                                // 利用規約同意チェックボックス
                                HStack(alignment: .top, spacing: 8) {
                                    Button(action: { agreedToTerms.toggle() }) {
                                        Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                                            .foregroundColor(agreedToTerms ? primaryOrange : .gray)
                                            .font(.system(size: isIPad ? 24 : 20))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Button(action: { showTerms = true }) {
                                            Text("利用規約")
                                                .foregroundColor(primaryOrange)
                                                .underline()
                                                .font(.system(size: isIPad ? 16 : 14))
                                        }
                                        Text("に同意します")
                                            .foregroundColor(.gray)
                                            .font(.system(size: isIPad ? 16 : 14))
                                    }
                                }
                                .padding(.vertical, 8)

                                // ログインボタン
                                Button(action: login) {
                                    HStack(spacing: 12) {
                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "arrow.right.circle.fill")
                                                .font(.system(size: isIPad ? 24 : 20))
                                            Text("ログイン")
                                                .font(.system(size: isIPad ? 22 : 18, weight: .bold))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: isIPad ? 70 : 56)
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
                                .disabled(isLoading || username.isEmpty || password.isEmpty || !agreedToTerms)
                                .opacity((isLoading || username.isEmpty || password.isEmpty || !agreedToTerms) ? 0.6 : 1.0)
                                .padding(.top, 8)

                                // 新規登録リンク
                                Button(action: { showRegister = true }) {
                                    HStack(spacing: 4) {
                                        Text("アカウントをお持ちでない方は")
                                            .foregroundColor(.gray)
                                        Text("新規登録")
                                            .foregroundColor(primaryOrange)
                                            .fontWeight(.semibold)
                                    }
                                    .font(.system(size: isIPad ? 18 : 14))
                                }
                                .padding(.top, 8)
                            }
                            .frame(maxWidth: isIPad ? 500 : .infinity) // iPadで最大幅を制限
                            .padding(.horizontal, isIPad ? 0 : 32)
                            .frame(maxWidth: .infinity) // 中央配置
                            .padding(.bottom, 50)

                            Spacer()
                                .frame(height: max(50, geometry.size.height * 0.1))
                        }
                        .frame(minHeight: geometry.size.height)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showRegister) {
                RegisterView()
            }
            .sheet(isPresented: $showTerms) {
                TermsOfServiceView(isAccepted: $agreedToTerms)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPadでもスタックスタイルを使用
    }

    // iPadかどうかを判定
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
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
