//
//  ContactsListView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct ContactsListView: View {
    @ObservedObject private var contactsService = ContactsService.shared
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var messagingService = MessagingService.shared

    @State private var showAddContact = false
    @State private var searchText = ""
    @State private var showMessageNotification = false
    @State private var notificationMessage = ""
    @State private var notificationFrom = ""

    var body: some View {
        NavigationView {
            ZStack {
                if contactsService.isLoading {
                    ProgressView("読み込み中...")
                } else if contactsService.contacts.isEmpty {
                    emptyStateView
                } else {
                    contactsList
                }

                // メッセージ通知バナー
                if showMessageNotification {
                    VStack {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(notificationFrom)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(notificationMessage)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding()
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                }
            }
            .navigationTitle("連絡先")
            .navigationBarItems(trailing: Button(action: { showAddContact = true }) {
                Image(systemName: "person.badge.plus")
            })
            .searchable(text: $searchText, prompt: "連絡先を検索")
            .sheet(isPresented: $showAddContact) {
                AddContactView()
            }
            .refreshable {
                await contactsService.fetchContacts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newMessageReceived)) { notification in
                handleNewMessageNotification(notification)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPadでもスタックスタイルを使用
        .task {
            await contactsService.fetchContacts()
        }
    }

    private func handleNewMessageNotification(_ notification: Notification) {
        guard let userId = notification.userInfo?["userId"] as? Int,
              let contact = contactsService.contacts.first(where: { $0.id == userId }),
              let lastMessage = messagingService.conversations[userId]?.last else {
            return
        }

        notificationFrom = contact.displayName
        notificationMessage = lastMessage.content

        withAnimation {
            showMessageNotification = true
        }

        // 5秒後に自動で消す
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation {
                showMessageNotification = false
            }
        }
    }

    private var contactsList: some View {
        List {
            if !filteredFavorites.isEmpty {
                Section("お気に入り") {
                    ForEach(filteredFavorites) { contact in
                        ContactRow(contact: contact)
                    }
                    .onDelete { indexSet in
                        deleteContacts(at: indexSet, from: filteredFavorites)
                    }
                }
            }

            if !filteredRegular.isEmpty {
                Section("すべての連絡先") {
                    ForEach(filteredRegular) { contact in
                        ContactRow(contact: contact)
                    }
                    .onDelete { indexSet in
                        deleteContacts(at: indexSet, from: filteredRegular)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
    }

    private func deleteContacts(at offsets: IndexSet, from contacts: [Contact]) {
        for index in offsets {
            let contact = contacts[index]
            Task {
                await contactsService.deleteContact(id: contact.id)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)
                .padding(.bottom, 8)

            Text("ChuTalkへようこそ！")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text("まだ連絡先が登録されていません。\n下のボタンから連絡先を追加して、\n通話やメッセージを始めましょう。")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: { showAddContact = true }) {
                Label("最初の連絡先を追加", systemImage: "person.badge.plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            // サーバー接続中の説明
            Text("※ サーバーとの接続中、一瞬画面が切り替わることがあります")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 24)
        }
        .padding()
    }

    private var filteredFavorites: [Contact] {
        let favorites = contactsService.favoriteContacts
        if searchText.isEmpty {
            return favorites
        }
        return favorites.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredRegular: [Contact] {
        let regular = contactsService.regularContacts
        if searchText.isEmpty {
            return regular
        }
        return regular.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }
}

struct ContactRow: View {
    let contact: Contact

    @ObservedObject private var contactsService = ContactsService.shared
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var messagingService = MessagingService.shared

    @State private var showCallOptions = false

    private var unreadCount: Int {
        messagingService.unreadCounts[contact.id] ?? 0
    }

    var body: some View {
        NavigationLink(destination: ChatView(contact: contact)) {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    if let imageUrl = contact.profileImageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            case .failure(_), .empty:
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text(String(contact.displayName.prefix(1)))
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                    )
                            @unknown default:
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 50, height: 50)
                            }
                        }
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(String(contact.displayName.prefix(1)))
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            )
                    }

                    if contact.isOnline {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    }
                }

                // Contact Info
                VStack(alignment: .leading, spacing: 4) {
                    // Last message time (moved to top right)
                    HStack(alignment: .top, spacing: 4) {
                        Text(contact.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        if let lastMessage = messagingService.conversations[contact.id]?.last {
                            Text(formatTime(lastMessage.timestamp))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("@\(contact.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                // Message Icon with Unread Badge
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "message.fill")
                        .foregroundColor(.green)
                        .frame(width: 40, height: 40)

                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 10))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red)
                            .clipShape(Circle())
                            .frame(minWidth: 18, minHeight: 18)
                            .offset(x: 8, y: -8)
                    }
                }

                // Call Button
                Button(action: {
                    showCallOptions = true
                }) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                // Favorite Icon
                Button(action: {
                    contactsService.toggleFavorite(contact)
                }) {
                    Image(systemName: contact.isFavorite ? "star.fill" : "star")
                        .foregroundColor(contact.isFavorite ? .yellow : .gray)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
        }
        .actionSheet(isPresented: $showCallOptions) {
            ActionSheet(
                title: Text(contact.displayName),
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
    }

    private func startCall(isVideo: Bool) {
        Task {
            await callManager.startCall(to: contact, isVideo: isVideo)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        } else {
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var contactsService = ContactsService.shared

    @State private var username = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("連絡先を追加")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 40)

                VStack(spacing: 16) {
                    TextField("ユーザーIDを入力", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: addContact) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("追加")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(Constants.UI.cornerRadius)
                    .disabled(isLoading || username.isEmpty)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationBarItems(leading: Button("キャンセル") {
                dismiss()
            })
            .alert("追加完了", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("連絡先が追加されました")
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // iPadでもスタックスタイルを使用
    }

    private func addContact() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await contactsService.addContact(username: username)

                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
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
    ContactsListView()
}
