//
//  SettingsView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var authService = AuthService.shared
    @AppStorage(Constants.UserDefaultsKeys.isVideoEnabledByDefault) private var isVideoEnabledByDefault = true
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section {
                    if let user = authService.currentUser {
                        HStack(spacing: 16) {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Text(String(user.displayName.prefix(1)))
                                        .font(.title)
                                        .foregroundColor(.blue)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)

                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                // Call Settings
                Section("通話設定") {
                    Toggle("デフォルトでビデオを有効にする", isOn: $isVideoEnabledByDefault)
                }

                // Future Features (Placeholder)
                Section("将来の機能") {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.gray)
                        Text("通話録音")
                        Spacer()
                        Text("近日公開")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.gray)
                        Text("文字起こし")
                        Spacer()
                        Text("近日公開")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // About Section
                Section("アプリについて") {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("サーバー")
                        Spacer()
                        Text(Constants.Server.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Logout Section
                Section {
                    Button(action: { showLogoutConfirmation = true }) {
                        HStack {
                            Spacer()
                            Text("ログアウト")
                                .foregroundColor(.red)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .confirmationDialog("ログアウトしますか?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) {
                    authService.logout()
                }
                Button("キャンセル", role: .cancel) {}
            }
        }
    }
}

#Preview {
    SettingsView()
}
