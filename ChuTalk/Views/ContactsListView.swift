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

    @State private var showAddContact = false
    @State private var searchText = ""

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
        }
        .task {
            await contactsService.fetchContacts()
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
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("連絡先がありません")
                .font(.headline)
                .foregroundColor(.secondary)

            Button(action: { showAddContact = true }) {
                Text("連絡先を追加")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
        }
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

    @State private var showCallOptions = false

    var body: some View {
        NavigationLink(destination: ChatView(contact: contact)) {
            HStack(spacing: 12) {
                // Avatar
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Text(String(contact.displayName.prefix(1)))
                                .font(.headline)
                                .foregroundColor(.blue)
                        )

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
                    Text(contact.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("@\(contact.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

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
