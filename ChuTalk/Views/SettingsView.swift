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
    @State private var showShareSheet = false
    @State private var logFileURL: URL?
    @State private var showLogAlert = false
    @State private var logAlertMessage = ""
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var profileImage: UIImage?

    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section {
                    if let user = authService.currentUser {
                        HStack(spacing: 16) {
                            Button(action: { showImagePicker = true }) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let profileImage = profileImage {
                                        Image(uiImage: profileImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(Color.blue.opacity(0.2))
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Text(String(user.displayName.prefix(1)))
                                                    .font(.title)
                                                    .foregroundColor(.blue)
                                            )
                                    }

                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName)
                                    .font(.headline)

                                Text("@\(user.username)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Text("タップして画像を変更")
                                    .font(.caption)
                                    .foregroundColor(.blue)
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

                // Debug Section
                Section("デバッグ") {
                    Button(action: exportLogs) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                            Text("デバッグログをエクスポート")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                    }

                    Button(action: clearLogs) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("デバッグログをクリア")
                        }
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
            .sheet(isPresented: $showShareSheet) {
                if let url = logFileURL {
                    ActivityViewController(activityItems: [url])
                }
            }
            .alert("ログ情報", isPresented: $showLogAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(logAlertMessage)
            }
            .sheet(isPresented: $showImagePicker) {
                ProfileImagePicker(selectedImage: $profileImage)
            }
            .onAppear {
                loadProfileImage()
            }
            .onChange(of: profileImage) { newImage in
                if let image = newImage {
                    saveProfileImage(image)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPadでもスタックスタイルを使用
    }

    private func exportLogs() {
        // まずテストログを書き込む
        FileLogger.shared.log("Export logs button tapped", category: "SettingsView")

        if let url = FileLogger.shared.getLogFileURL() {
            // ファイルが存在するか確認
            if FileManager.default.fileExists(atPath: url.path) {
                if let contents = try? String(contentsOf: url, encoding: .utf8) {
                    if contents.isEmpty {
                        logAlertMessage = "ログファイルは空です。\nパス: \(url.path)"
                        showLogAlert = true
                    } else {
                        logFileURL = url
                        showShareSheet = true
                        logAlertMessage = "ログファイルサイズ: \(contents.count) バイト"
                        print("📝 SettingsView: Log file size: \(contents.count) bytes")
                    }
                } else {
                    logAlertMessage = "ログファイルを読み込めません。\nパス: \(url.path)"
                    showLogAlert = true
                }
            } else {
                logAlertMessage = "ログファイルが見つかりません。\n期待されるパス: \(url.path)\n\nアプリを再起動してから、何か操作を行ってください。"
                showLogAlert = true
            }
        } else {
            logAlertMessage = "ログファイルのURLを取得できません。"
            showLogAlert = true
        }
    }

    private func clearLogs() {
        FileLogger.shared.clearLogs()
        logAlertMessage = "ログをクリアしました。"
        showLogAlert = true
    }

    private func loadProfileImage() {
        if let imageData = UserDefaults.standard.data(forKey: "profileImage"),
           let image = UIImage(data: imageData) {
            profileImage = image
            print("✅ SettingsView: Loaded profile image from UserDefaults")
        }
    }

    private func saveProfileImage(_ image: UIImage) {
        // Save locally first for immediate display
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            UserDefaults.standard.set(imageData, forKey: "profileImage")
            print("✅ SettingsView: Saved profile image to UserDefaults")
        }

        // Upload to server
        Task {
            do {
                let imageUrl = try await APIService.shared.uploadImage(image)
                print("✅ SettingsView: Uploaded image to server: \(imageUrl)")

                let updatedUser = try await APIService.shared.updateProfileImage(imageUrl)
                print("✅ SettingsView: Updated profile with image URL")

                await MainActor.run {
                    authService.currentUser = updatedUser
                }
            } catch {
                print("❌ SettingsView: Failed to upload profile image: \(error)")
            }
        }
    }
}

// ProfileImagePicker for selecting profile images
struct ProfileImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImagePicker

        init(_ parent: ProfileImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// ActivityViewController for sharing files
struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
