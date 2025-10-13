//
//  MessagingService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine

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
                self.conversations[userId] = messages.sorted { $0.timestamp < $1.timestamp }
                self.updateUnreadCounts()

                // Save to local storage
                LocalStorageManager.shared.saveMessages(Array(self.conversations.values.flatMap { $0 }))

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
        for i in 0..<messages.count {
            if !messages[i].isRead && !messages[i].isSentByCurrentUser {
                messages[i].isRead = true
                hasChanges = true

                // Update in local storage
                LocalStorageManager.shared.updateMessage(messages[i])
            }
        }

        if hasChanges {
            conversations[userId] = messages
            updateUnreadCounts()
            print("✅ MessagingService: Marked messages as read for \(userId)")
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
    }

    func clearMessages(with userId: Int) async {
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
