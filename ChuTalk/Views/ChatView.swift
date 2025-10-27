//
//  ChatView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI
import AVKit

struct ChatView: View {
    let contact: Contact

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var messagingService = MessagingService.shared
    @ObservedObject private var callManager = CallManager.shared

    @State private var messageText = ""
    @State private var showCallOptions = false
    @State private var showDeleteAlert = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var isUploadingImage = false
    @State private var showUploadError = false
    @State private var uploadErrorMessage = ""
    @State private var showVideoPicker = false
    @State private var selectedVideoURL: URL?
    @State private var isUploadingVideo = false
    @State private var showMediaOptions = false
    @State private var showReportSheet = false
    @State private var reportReason = ""
    @State private var showBlockAlert = false
    @State private var showReportSuccess = false
    @State private var selectedMessageForReport: Message?

    // Computed property to get messages from MessagingService
    private var messages: [Message] {
        messagingService.conversations[contact.id] ?? []
    }

    // Draft message key for UserDefaults
    private var draftKey: String {
        "draft_message_\(contact.id)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                contact: contact,
                                onReportMessage: { message in
                                    selectedMessageForReport = message
                                    showReportSheet = true
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await refreshMessages()
                }
                .onChange(of: messages.count) { _ in
                    // Scroll to bottom when new message arrives
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom on appear
                    if let lastMessage = messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }

                    // Load draft message
                    loadDraft()
                }
            }

            // Message Input
            HStack(alignment: .bottom, spacing: 12) {
                // Media picker button
                Button(action: { showMediaOptions = true }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                }
                .disabled(isUploadingImage || isUploadingVideo)
                .padding(.bottom, 6)

                ZStack(alignment: .topLeading) {
                    // TextEditor for multiline input
                    TextEditor(text: $messageText)
                        .frame(minHeight: 36, maxHeight: 50)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .autocorrectionDisabled()
                        .onChange(of: messageText) { _ in
                            saveDraft()
                        }

                    // Placeholder
                    if messageText.isEmpty {
                        Text("メッセージを入力")
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 36)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                Button(action: sendMessage) {
                    if isUploadingImage || isUploadingVideo {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploadingImage || isUploadingVideo)
                .padding(.bottom, 4)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: HStack(spacing: 16) {
            Menu {
                Button(action: { showReportSheet = true }) {
                    Label("ユーザーを通報", systemImage: "exclamationmark.triangle")
                }

                Button(role: .destructive, action: { showBlockAlert = true }) {
                    Label("ユーザーをブロック", systemImage: "hand.raised")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.blue)
            }

            Button(action: { showDeleteAlert = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }

            Button(action: { showCallOptions = true }) {
                Image(systemName: "phone.fill")
                    .foregroundColor(.blue)
            }
        })
        .alert("会話履歴を削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                Task {
                    await messagingService.clearMessages(with: contact.id)
                    dismiss()
                }
            }
        } message: {
            Text("この連絡先との会話履歴を削除しますか？")
        }
        .confirmationDialog("通話", isPresented: $showCallOptions, titleVisibility: .visible) {
            Button("ビデオ通話") {
                startCall(isVideo: true)
            }
            Button("音声通話") {
                startCall(isVideo: false)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .onAppear {
            print("📱 ChatView: onAppear - marking messages as read for contact \(contact.id)")
            markMessagesAsRead()
            setupNewMessageListener()
            messagingService.startPolling(for: contact.id)
        }
        .onDisappear {
            print("📱 ChatView: onDisappear - stopping polling for contact \(contact.id)")
            // Mark as read again when leaving the chat
            markMessagesAsRead()
            messagingService.stopPolling()
        }
        .onChange(of: messages.count) { newCount in
            // Mark messages as read whenever new messages arrive while in chat
            print("📱 ChatView: Message count changed to \(newCount), marking as read")
            markMessagesAsRead()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPicker(videoURL: $selectedVideoURL)
        }
        .onChange(of: selectedImage) { image in
            if let image = image {
                sendImageMessage(image: image)
            }
        }
        .onChange(of: selectedVideoURL) { url in
            if let url = url {
                sendVideoMessage(videoURL: url)
            }
        }
        .confirmationDialog("メディアを選択", isPresented: $showMediaOptions, titleVisibility: .visible) {
            Button("写真") {
                showImagePicker = true
            }
            Button("動画") {
                showVideoPicker = true
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("エラー", isPresented: $showUploadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploadErrorMessage)
        }
        .sheet(isPresented: $showReportSheet) {
            NavigationView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedMessageForReport != nil {
                        Text("このメッセージを通報する理由を選択してください")
                            .font(.headline)
                            .padding(.horizontal)
                    } else {
                        Text("ユーザーを通報する理由を選択してください")
                            .font(.headline)
                            .padding(.horizontal)
                    }

                    List {
                        Button(action: { submitReport("不適切なメッセージ") }) {
                            Text("不適切なメッセージ")
                        }
                        Button(action: { submitReport("嫌がらせ・誹謗中傷") }) {
                            Text("嫌がらせ・誹謗中傷")
                        }
                        Button(action: { submitReport("スパム・宣伝") }) {
                            Text("スパム・宣伝")
                        }
                        Button(action: { submitReport("性的な内容") }) {
                            Text("性的な内容")
                        }
                        Button(action: { submitReport("暴力的な内容") }) {
                            Text("暴力的な内容")
                        }
                        Button(action: { submitReport("その他") }) {
                            Text("その他")
                        }
                    }
                }
                .navigationTitle(selectedMessageForReport != nil ? "メッセージを通報" : "ユーザーを通報")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("キャンセル") {
                            showReportSheet = false
                            selectedMessageForReport = nil
                        }
                    }
                }
            }
        }
        .alert("ユーザーをブロック", isPresented: $showBlockAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                blockUser()
            }
        } message: {
            Text("このユーザーをブロックしますか？ブロックすると、このユーザーからのメッセージや通話を受信しなくなります。")
        }
        .alert("通報完了", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("通報を受け付けました。24時間以内に確認させていただきます。")
        }
    }

    private func refreshMessages() async {
        await messagingService.refreshMessages(for: contact.id)
    }

    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            print("⚠️ ChatView: Message is empty, not sending")
            return
        }

        print("📤 ChatView: Send button pressed for contact \(contact.id)")
        print("📤 ChatView: Message text: \(trimmedText)")

        Task {
            let success = await messagingService.sendMessage(to: contact.id, content: trimmedText)

            await MainActor.run {
                if success {
                    print("✅ ChatView: Message sent successfully, clearing text field")
                    messageText = ""
                    clearDraft()
                } else {
                    print("⚠️ ChatView: Message send failed, keeping text in field")
                }
            }
        }
    }

    private func loadDraft() {
        if let draft = UserDefaults.standard.string(forKey: draftKey) {
            messageText = draft
        }
    }

    private func saveDraft() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearDraft()
        } else {
            UserDefaults.standard.set(messageText, forKey: draftKey)
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: draftKey)
    }

    private func markMessagesAsRead() {
        messagingService.markMessagesAsRead(for: contact.id)
    }

    private func setupNewMessageListener() {
        NotificationCenter.default.addObserver(
            forName: .newMessageReceived,
            object: nil,
            queue: .main
        ) { notification in
            if let userId = notification.userInfo?["userId"] as? Int,
               userId == contact.id {
                markMessagesAsRead()
            }
        }
    }

    private func startCall(isVideo: Bool) {
        Task {
            await callManager.startCall(to: contact, isVideo: isVideo)
        }
    }

    private func submitReport(_ reason: String) {
        showReportSheet = false
        let messageId = selectedMessageForReport?.serverId
        selectedMessageForReport = nil

        Task {
            do {
                _ = try await APIService.shared.reportUser(
                    reportedUserId: contact.id,
                    messageId: messageId,
                    reason: reason
                )
                await MainActor.run {
                    showReportSuccess = true
                }
            } catch {
                print("❌ Failed to submit report: \(error)")
                await MainActor.run {
                    uploadErrorMessage = "通報の送信に失敗しました。もう一度お試しください。"
                    showUploadError = true
                }
            }
        }
    }

    private func blockUser() {
        Task {
            do {
                _ = try await APIService.shared.blockUser(userId: contact.id)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("❌ Failed to block user: \(error)")
                await MainActor.run {
                    uploadErrorMessage = "ブロックに失敗しました。もう一度お試しください。"
                    showUploadError = true
                }
            }
        }
    }

    private func sendImageMessage(image: UIImage) {
        isUploadingImage = true

        Task {
            let success = await messagingService.sendImageMessage(to: contact.id, image: image)

            await MainActor.run {
                isUploadingImage = false
                if success {
                    selectedImage = nil
                    print("✅ ChatView: Image sent successfully")
                } else {
                    print("⚠️ ChatView: Image send failed")
                    uploadErrorMessage = "画像の送信に失敗しました。画像サイズが大きすぎる可能性があります。"
                    showUploadError = true
                }
            }
        }
    }

    private func sendVideoMessage(videoURL: URL) {
        isUploadingVideo = true

        Task {
            let success = await messagingService.sendVideoMessage(to: contact.id, videoUrl: videoURL)

            await MainActor.run {
                isUploadingVideo = false
                if success {
                    selectedVideoURL = nil
                    print("✅ ChatView: Video sent successfully")
                } else {
                    print("⚠️ ChatView: Video send failed")
                    uploadErrorMessage = "動画の送信に失敗しました。動画サイズが大きすぎる可能性があります。"
                    showUploadError = true
                }
            }
        }
    }
}

// MARK: - Image Picker

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Video Picker

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeHigh
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoPicker

        init(_ parent: VideoPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let contact: Contact
    let onReportMessage: (Message) -> Void

    @State private var showSaveAlert = false
    @State private var saveSuccess = false
    @State private var showImageViewer = false

    var body: some View {
        HStack {
            if message.isSentByCurrentUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if message.messageType == .image {
                        if let imageUrl = message.imageUrl {
                            AsyncImage(url: URL(string: imageUrl)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 200, height: 200)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: 260, maxHeight: 300)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .onTapGesture {
                                            showImageViewer = true
                                        }
                                        .contextMenu {
                                            Button(action: {
                                                saveImage(image: image)
                                            }) {
                                                Label("写真を保存", systemImage: "square.and.arrow.down")
                                            }
                                        }
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                        .frame(width: 200, height: 200)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    } else if message.messageType == .video {
                        if let videoUrl = message.videoUrl, let url = URL(string: videoUrl) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(width: 260, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        Text(message.content)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .frame(maxWidth: 260, alignment: .trailing)
                    }

                    HStack(spacing: 4) {
                        Text(formatTime(message.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // デバッグ用：既読状態を常に表示
                        Text("[\(message.isRead ? "既読" : "未読")]")
                            .font(.caption2)
                            .foregroundColor(message.isRead ? .green : .red)

                        if message.isRead {
                            // ダブルチェックマーク（既読）
                            HStack(spacing: -2) {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            // シングルチェックマーク（送信済み）
                            Image(systemName: "checkmark")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if message.messageType == .image {
                        if let imageUrl = message.imageUrl {
                            AsyncImage(url: URL(string: imageUrl)) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 200, height: 200)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: 260, maxHeight: 300)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .onTapGesture {
                                            showImageViewer = true
                                        }
                                        .contextMenu {
                                            Button(action: {
                                                saveImage(image: image)
                                            }) {
                                                Label("写真を保存", systemImage: "square.and.arrow.down")
                                            }

                                            Button(action: {
                                                onReportMessage(message)
                                            }) {
                                                Label("このメッセージを通報", systemImage: "exclamationmark.triangle")
                                            }
                                        }
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.gray)
                                        .frame(width: 200, height: 200)
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        }
                    } else if message.messageType == .video {
                        if let videoUrl = message.videoUrl, let url = URL(string: videoUrl) {
                            VideoPlayer(player: AVPlayer(url: url))
                                .frame(width: 260, height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        Text(message.content)
                            .padding(12)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(16)
                            .frame(maxWidth: 260, alignment: .leading)
                            .contextMenu {
                                Button(action: {
                                    onReportMessage(message)
                                }) {
                                    Label("このメッセージを通報", systemImage: "exclamationmark.triangle")
                                }
                            }
                    }

                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .alert(saveSuccess ? "保存完了" : "保存失敗", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveSuccess ? "写真をライブラリに保存しました" : "写真の保存に失敗しました")
        }
        .fullScreenCover(isPresented: $showImageViewer) {
            if let imageUrl = message.imageUrl {
                ImageViewer(imageUrl: imageUrl, isPresented: $showImageViewer)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "昨日 " + formatter.string(from: date)
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
            return formatter.string(from: date)
        }
    }

    private func saveImage(image: Image) {
        // SwiftUI Imageからは直接UIImageを取得できないため、
        // URLから再度ダウンロードする必要があります
        guard let imageUrl = message.imageUrl,
              let url = URL(string: imageUrl) else {
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                    await MainActor.run {
                        saveSuccess = true
                        showSaveAlert = true
                    }
                }
            } catch {
                print("❌ Failed to save image: \(error)")
                await MainActor.run {
                    saveSuccess = false
                    showSaveAlert = true
                }
            }
        }
    }
}

// MARK: - Image Viewer

struct ImageViewer: View {
    let imageUrl: String
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: URL(string: imageUrl)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    // 最小スケールを1.0に制限
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            lastScale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { value in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            // ダブルタップでズームイン/リセット
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 100))
                        .foregroundColor(.white.opacity(0.5))
                @unknown default:
                    EmptyView()
                }
            }

            // 閉じるボタン
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }
}

#Preview {
    NavigationView {
        ChatView(contact: Contact(
            id: 1,
            username: "testuser",
            displayName: "Test User",
            isOnline: true,
            isFavorite: false
        ))
    }
}
