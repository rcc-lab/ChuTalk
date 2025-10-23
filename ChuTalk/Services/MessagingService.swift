//
//  MessagingService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import UIKit

class MessagingService: ObservableObject {
    static let shared = MessagingService()

    @Published var conversations: [Int: [Message]] = [:]
    @Published var unreadCounts: [Int: Int] = [:]

    private var cancellables = Set<AnyCancellable>()
    private var messageTimer: Timer?
    private var activeConversationUserId: Int?

    private init() {
        setupMessageListener()
        loadLocalMessages()
    }

    deinit {
        stopPolling()
    }

    private func loadLocalMessages() {
        guard let currentUserId = AuthService.shared.currentUser?.id else { return }
        let allMessages = LocalStorageManager.shared.loadMessages()

        // Group messages by conversation
        for message in allMessages {
            let otherUserId = message.senderId == currentUserId ? message.receiverId : message.senderId
            if conversations[otherUserId] == nil {
                conversations[otherUserId] = []
            }
            conversations[otherUserId]?.append(message)
        }

        // Sort messages in each conversation
        for (userId, _) in conversations {
            conversations[userId]?.sort { $0.timestamp < $1.timestamp }
        }

        updateUnreadCounts()
        print("✅ MessagingService: Loaded \(allMessages.count) messages from local storage")
    }

    private func setupMessageListener() {
        SocketService.shared.onMessageReceived = { [weak self] from, body, timestamp in
            self?.handleReceivedMessage(from: from, body: body, timestamp: timestamp)
        }
    }

    // Fetch message history from server
    func fetchMessages(for userId: Int) async {
        guard let currentUserId = AuthService.shared.currentUser?.id else { return }

        do {
            let messages = try await APIService.shared.getMessages(userId: userId)

            await MainActor.run {
                // サーバーから取得したメッセージの既読状態を反映
                // 送信メッセージ（自分→相手）の場合、サーバーのis_readが相手の既読状態を表す
                // 受信メッセージ（相手→自分）の場合、ローカルの既読状態を使用
                var updatedMessages = messages.sorted { $0.timestamp < $1.timestamp }

                FileLogger.shared.log("📊 Processing \(updatedMessages.count) messages for user \(userId), currentUserId=\(currentUserId)", category: "MessagingService")
                print("📊 MessagingService: Processing \(updatedMessages.count) messages for user \(userId), currentUserId=\(currentUserId)")

                // 既存のローカルメッセージと比較して、受信メッセージの既読状態を保持
                for i in 0..<updatedMessages.count {
                    let msg = updatedMessages[i]
                    let logMsg = "📊 Message \(i): sender=\(msg.senderId), receiver=\(msg.receiverId), isRead=\(msg.isRead), isSentByMe=\(msg.isSentByCurrentUser)"
                    FileLogger.shared.log(logMsg, category: "MessagingService")
                    print(logMsg)

                    // 受信メッセージの場合、ローカルの既読状態を優先
                    if msg.receiverId == currentUserId {
                        if let existingMessages = self.conversations[userId],
                           let existingMsg = existingMessages.first(where: { $0.serverId == msg.serverId }) {
                            updatedMessages[i].isRead = existingMsg.isRead
                            let log = "  → 受信メッセージ: ローカルの既読状態を使用 isRead=\(existingMsg.isRead)"
                            FileLogger.shared.log(log, category: "MessagingService")
                            print(log)
                        } else {
                            let log = "  → 受信メッセージ: 既存メッセージなし、サーバーの状態を使用 isRead=\(msg.isRead)"
                            FileLogger.shared.log(log, category: "MessagingService")
                            print(log)
                        }
                    } else {
                        // 送信メッセージの場合、サーバーの既読状態をそのまま使用（相手の既読状態）
                        let log = "  → 送信メッセージ: サーバーの既読状態を使用 isRead=\(msg.isRead)"
                        FileLogger.shared.log(log, category: "MessagingService")
                        print(log)
                    }
                }

                self.conversations[userId] = updatedMessages
                self.updateUnreadCounts()

                // Update local storage for this specific user only
                // 1. Load all existing messages
                var allMessages = LocalStorageManager.shared.loadMessages()

                // 2. Remove old messages for this user
                allMessages.removeAll { message in
                    (message.senderId == userId && message.receiverId == currentUserId) ||
                    (message.senderId == currentUserId && message.receiverId == userId)
                }

                // 3. Add new messages from server
                allMessages.append(contentsOf: updatedMessages)

                // 4. Save updated messages
                LocalStorageManager.shared.saveMessages(allMessages)

                print("✅ MessagingService: Fetched \(messages.count) messages from server for user \(userId)")
            }
        } catch {
            print("❌ MessagingService: Failed to fetch messages - \(error)")
            // Use local storage as fallback
            await MainActor.run {
                let localMessages = LocalStorageManager.shared.getMessages(for: userId, currentUserId: currentUserId)
                self.conversations[userId] = localMessages
                self.updateUnreadCounts()
            }
        }
    }

    func sendMessage(to userId: Int, content: String) async -> Bool {
        guard let currentUserId = AuthService.shared.currentUser?.id else {
            print("❌ MessagingService: No current user")
            return false
        }

        print("📤 MessagingService: Attempting to send message to user \(userId)")
        print("📤 MessagingService: Message content: \(content)")

        do {
            let message = try await APIService.shared.sendMessage(receiverId: userId, body: content)

            await MainActor.run {
                // Add to local conversations
                if self.conversations[userId] == nil {
                    self.conversations[userId] = []
                }
                self.conversations[userId]?.append(message)

                // Save to local storage
                LocalStorageManager.shared.addMessage(message)

                print("✅ MessagingService: Sent message via API to \(userId)")

                // Also send via Socket.IO for real-time delivery and push notifications
                SocketService.shared.sendMessage(to: userId, body: content)
                print("✅ MessagingService: Sent message via Socket.IO to \(userId)")
            }
            return true
        } catch {
            print("❌ MessagingService: Failed to send via API - \(error)")
            if let apiError = error as? APIError {
                print("❌ MessagingService: API Error details: \(apiError.localizedDescription)")
            }

            // Create local message even if API fails
            let localMessage = Message(
                senderId: currentUserId,
                receiverId: userId,
                content: content
            )

            await MainActor.run {
                if self.conversations[userId] == nil {
                    self.conversations[userId] = []
                }
                self.conversations[userId]?.append(localMessage)
                LocalStorageManager.shared.addMessage(localMessage)
                print("💾 MessagingService: Saved message locally (API failed)")
            }
            return false
        }
    }

    func sendImageMessage(to userId: Int, image: UIImage) async -> Bool {
        guard let currentUserId = AuthService.shared.currentUser?.id else {
            print("❌ MessagingService: No current user")
            return false
        }

        print("📤 MessagingService: Attempting to send image to user \(userId)")

        do {
            // First, upload the image
            let imageUrl = try await APIService.shared.uploadImage(image)
            print("✅ MessagingService: Image uploaded to \(imageUrl)")

            // Then send the message with the image URL
            let message = try await APIService.shared.sendMessage(
                receiverId: userId,
                body: "[画像]",
                messageType: "image",
                imageUrl: imageUrl
            )

            await MainActor.run {
                // Add to local conversations
                if self.conversations[userId] == nil {
                    self.conversations[userId] = []
                }
                self.conversations[userId]?.append(message)

                // Save to local storage
                LocalStorageManager.shared.addMessage(message)

                print("✅ MessagingService: Sent image message via API to \(userId)")

                // Also send via Socket.IO for real-time delivery
                SocketService.shared.sendMessage(to: userId, body: "[画像]")
                print("✅ MessagingService: Sent image notification via Socket.IO to \(userId)")
            }
            return true
        } catch {
            print("❌ MessagingService: Failed to send image - \(error)")
            FileLogger.shared.log("❌ Failed to send image: \(error)", category: "MessagingService")
            if let apiError = error as? APIError {
                print("❌ MessagingService: API Error details: \(apiError.localizedDescription)")
                FileLogger.shared.log("❌ API Error: \(apiError.localizedDescription)", category: "MessagingService")
            }
            if let urlError = error as? URLError {
                print("❌ MessagingService: URL Error: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))")
                FileLogger.shared.log("❌ URL Error: \(urlError.localizedDescription) (Code: \(urlError.code.rawValue))", category: "MessagingService")
            }
            return false
        }
    }

    func sendVideoMessage(to userId: Int, videoUrl: URL) async -> Bool {
        guard let currentUserId = AuthService.shared.currentUser?.id else {
            print("❌ MessagingService: No current user")
            return false
        }

        print("📤 MessagingService: Attempting to send video to user \(userId)")

        do {
            // First, upload the video
            let uploadedVideoUrl = try await APIService.shared.uploadVideo(url: videoUrl)
            print("✅ MessagingService: Video uploaded to \(uploadedVideoUrl)")

            // Then send the message with the video URL
            let message = try await APIService.shared.sendMessage(
                receiverId: userId,
                body: "[動画]",
                messageType: "video",
                videoUrl: uploadedVideoUrl
            )

            await MainActor.run {
                // Add to local conversations
                if self.conversations[userId] == nil {
                    self.conversations[userId] = []
                }
                self.conversations[userId]?.append(message)

                // Save to local storage
                LocalStorageManager.shared.addMessage(message)

                print("✅ MessagingService: Sent video message via API to \(userId)")

                // Also send via Socket.IO for real-time delivery
                SocketService.shared.sendMessage(to: userId, body: "[動画]")
                print("✅ MessagingService: Sent video notification via Socket.IO to \(userId)")
            }
            return true
        } catch {
            print("❌ MessagingService: Failed to send video - \(error)")
            if let apiError = error as? APIError {
                print("❌ MessagingService: API Error details: \(apiError.localizedDescription)")
            }
            return false
        }
    }

    private func handleReceivedMessage(from: Int, body: String, timestamp: Date) {
        guard let currentUserId = AuthService.shared.currentUser?.id else { return }

        // Ignore messages from ourselves (echo from socket)
        if from == currentUserId {
            print("⚠️ MessagingService: Ignoring message from self (echo)")
            return
        }

        let message = Message(
            senderId: from,
            receiverId: currentUserId,
            content: body,
            timestamp: timestamp,
            isRead: false
        )

        // Check if message already exists
        if let existingMessages = conversations[from],
           existingMessages.contains(where: { $0.timestamp == message.timestamp && $0.content == message.content }) {
            print("⚠️ MessagingService: Message already exists, skipping")
            return
        }

        // Add to conversations
        if conversations[from] == nil {
            conversations[from] = []
        }
        conversations[from]?.append(message)
        conversations[from]?.sort { $0.timestamp < $1.timestamp }

        // Save to local storage
        LocalStorageManager.shared.addMessage(message)

        // Update unread count
        updateUnreadCounts()

        // Post notification for new message
        NotificationCenter.default.post(name: .newMessageReceived, object: nil, userInfo: ["userId": from])

        print("✅ MessagingService: Received message from \(from)")
    }

    func markMessagesAsRead(for userId: Int) {
        guard var messages = conversations[userId] else { return }

        var hasChanges = false
        var hasUnreadFromOther = false

        for i in 0..<messages.count {
            if !messages[i].isSentByCurrentUser {
                // Track if there are any messages from the other user (read or unread)
                hasUnreadFromOther = true

                if !messages[i].isRead {
                    messages[i].isRead = true
                    hasChanges = true

                    // Update in local storage
                    LocalStorageManager.shared.updateMessage(messages[i])
                }
            }
        }

        if hasChanges {
            conversations[userId] = messages
            updateUnreadCounts()
            let log = "✅ Marked messages as read for user \(userId)"
            FileLogger.shared.log(log, category: "MessagingService")
            print("✅ MessagingService: \(log)")
        }

        // Always notify server if there are any messages from the other user
        // This ensures the server knows we've viewed the conversation even if messages
        // were already marked as read locally
        if hasUnreadFromOther {
            Task {
                do {
                    FileLogger.shared.log("📤 Notifying server about read status for user \(userId)", category: "MessagingService")
                    try await APIService.shared.markMessagesAsRead(userId: userId)
                    let successLog = "✅ Server notified of read status for user \(userId)"
                    FileLogger.shared.log(successLog, category: "MessagingService")
                    print("✅ MessagingService: \(successLog)")
                } catch {
                    let errorLog = "⚠️ Failed to notify server of read status - \(error)"
                    FileLogger.shared.log(errorLog, category: "MessagingService")
                    print("⚠️ MessagingService: \(errorLog)")
                }
            }
        }
    }

    func getMessages(for userId: Int) -> [Message] {
        return conversations[userId] ?? []
    }

    private func updateUnreadCounts() {
        for (userId, messages) in conversations {
            let unreadCount = messages.filter { !$0.isRead && !$0.isSentByCurrentUser }.count
            unreadCounts[userId] = unreadCount
        }

        // アプリバッジを更新
        updateAppBadge()
    }

    private func updateAppBadge() {
        // 全ての未読数を合計
        let totalUnreadCount = unreadCounts.values.reduce(0, +)

        // メインスレッドでバッジを更新
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(totalUnreadCount) { error in
                    if let error = error {
                        print("❌ MessagingService: Failed to update badge - \(error)")
                    } else {
                        print("✅ MessagingService: Updated badge count to \(totalUnreadCount)")
                    }
                }
            } else {
                // iOS 15の場合はUIApplicationで設定
                UIApplication.shared.applicationIconBadgeNumber = totalUnreadCount
                print("✅ MessagingService: Updated badge count to \(totalUnreadCount) (iOS 15)")
            }
        }
    }

    /// バッジをクリア（ログアウト時などに使用）
    func clearAppBadge() {
        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(0) { error in
                    if let error = error {
                        print("❌ MessagingService: Failed to clear badge - \(error)")
                    } else {
                        print("✅ MessagingService: Cleared badge")
                    }
                }
            } else {
                // iOS 15の場合はUIApplicationで設定
                UIApplication.shared.applicationIconBadgeNumber = 0
                print("✅ MessagingService: Cleared badge (iOS 15)")
            }
        }
    }

    func clearMessages(with userId: Int) async {
        // Delete from server first
        do {
            try await APIService.shared.deleteMessages(userId: userId)
            print("✅ MessagingService: Deleted messages from server for user \(userId)")
        } catch {
            print("⚠️ MessagingService: Failed to delete from server - \(error)")
        }

        await MainActor.run {
            conversations.removeValue(forKey: userId)
            unreadCounts.removeValue(forKey: userId)
        }

        // Delete from local storage
        guard let currentUserId = AuthService.shared.currentUser?.id else { return }
        var allMessages = LocalStorageManager.shared.loadMessages()
        allMessages.removeAll { message in
            (message.senderId == userId && message.receiverId == currentUserId) ||
            (message.senderId == currentUserId && message.receiverId == userId)
        }
        LocalStorageManager.shared.saveMessages(allMessages)

        print("✅ MessagingService: Cleared messages with user \(userId)")
    }

    func deleteConversation(with userId: Int) {
        conversations.removeValue(forKey: userId)
        unreadCounts.removeValue(forKey: userId)

        // Delete from local storage
        guard let currentUserId = AuthService.shared.currentUser?.id else { return }
        var allMessages = LocalStorageManager.shared.loadMessages()
        allMessages.removeAll { message in
            (message.senderId == userId && message.receiverId == currentUserId) ||
            (message.senderId == currentUserId && message.receiverId == userId)
        }
        LocalStorageManager.shared.saveMessages(allMessages)

        print("✅ MessagingService: Deleted conversation with \(userId)")
    }

    // MARK: - Polling

    func startPolling(for contactId: Int) {
        stopPolling()
        activeConversationUserId = contactId

        // 初回の取得
        Task {
            await fetchMessages(for: contactId)
        }

        // 2秒ごとに新着メッセージをチェック
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchMessages(for: contactId)
            }
        }
        print("✅ MessagingService: Started polling every 2 seconds for user \(contactId)")
    }

    func stopPolling() {
        messageTimer?.invalidate()
        messageTimer = nil
        activeConversationUserId = nil
        print("✅ MessagingService: Stopped polling")
    }

    func refreshMessages(for userId: Int) async {
        await fetchMessages(for: userId)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let newMessageReceived = Notification.Name("newMessageReceived")
}
