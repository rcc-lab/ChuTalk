//
//  ChatView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct ChatView: View {
    let contact: Contact

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var messagingService = MessagingService.shared
    @ObservedObject private var callManager = CallManager.shared

    @State private var messageText = ""
    @State private var showCallOptions = false
    @State private var showDeleteAlert = false

    // Computed property to get messages from MessagingService
    private var messages: [Message] {
        messagingService.conversations[contact.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
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
                }
            }

            // Message Input
            HStack(spacing: 12) {
                TextField("メッセージを入力", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: HStack(spacing: 16) {
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
        .actionSheet(isPresented: $showCallOptions) {
            ActionSheet(
                title: Text("通話"),
                buttons: [
                    .default(Text("ビデオ通話")) {
                        startCall(isVideo: true)
                    },
                    .default(Text("音声通話")) {
                        startCall(isVideo: false)
                    },
                    .cancel(Text("キャンセル"))
                ]
            )
        }
        .onAppear {
            markMessagesAsRead()
            setupNewMessageListener()
            messagingService.startPolling(for: contact.id)
        }
        .onDisappear {
            messagingService.stopPolling()
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
                } else {
                    print("⚠️ ChatView: Message send failed, keeping text in field")
                }
            }
        }
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
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isSentByCurrentUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .frame(maxWidth: 260, alignment: .trailing)

                    HStack(spacing: 4) {
                        Text(formatTime(message.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if message.isRead {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(16)
                        .frame(maxWidth: 260, alignment: .leading)

                    Text(formatTime(message.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "昨日 " + date.formatted(date: .omitted, time: .shortened)
        } else {
            formatter.dateFormat = "MM/dd HH:mm"
        }

        return formatter.string(from: date)
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
