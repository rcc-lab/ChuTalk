//
//  ContactsService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine

class ContactsService: ObservableObject {
    static let shared = ContactsService()

    @Published var contacts: [Contact] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupOnlineStatusObserver()
        loadLocalContacts()
    }

    private func loadLocalContacts() {
        // Load contacts from local storage on init
        self.contacts = LocalStorageManager.shared.loadContacts()
        print("✅ ContactsService: Loaded \(contacts.count) contacts from local storage")
    }

    private func setupOnlineStatusObserver() {
        NotificationCenter.default.publisher(for: .userStatusChanged)
            .sink { [weak self] _ in
                self?.updateOnlineStatuses()
            }
            .store(in: &cancellables)
    }

    func fetchContacts() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let fetchedContacts = try await APIService.shared.getContacts()

            await MainActor.run {
                self.contacts = fetchedContacts
                // Save to local storage
                LocalStorageManager.shared.saveContacts(fetchedContacts)
                self.updateOnlineStatuses()
                self.isLoading = false
                print("✅ ContactsService: Fetched \(fetchedContacts.count) contacts from server")
            }
        } catch {
            print("⚠️ ContactsService: Failed to fetch from server, using local storage - \(error)")
            await MainActor.run {
                // Use local storage as fallback
                self.contacts = LocalStorageManager.shared.loadContacts()
                self.updateOnlineStatuses()
                self.errorMessage = nil
                self.isLoading = false
            }
        }
    }

    func addContact(username: String) async throws {
        let response = try await APIService.shared.addContact(targetUsername: username)

        if response.ok, let contact = response.contact {
            await MainActor.run {
                self.contacts.append(contact)
                LocalStorageManager.shared.addContact(contact)
                self.updateOnlineStatuses()
                print("✅ ContactsService: Added contact from server - \(username)")
            }
        } else {
            throw APIError.serverError("Failed to add contact")
        }
    }

    func toggleFavorite(_ contact: Contact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index].isFavorite.toggle()
            LocalStorageManager.shared.updateContact(contacts[index])
            print("✅ ContactsService: Updated favorite status for \(contact.username)")
        }
    }

    func deleteContact(id: Int) async {
        do {
            try await APIService.shared.deleteContact(contactId: id)

            await MainActor.run {
                contacts.removeAll { $0.id == id }
                LocalStorageManager.shared.removeContact(id: id)
                print("✅ ContactsService: Deleted contact \(id)")
            }
        } catch {
            print("❌ ContactsService: Failed to delete contact - \(error)")
            // Even if server delete fails, remove from local storage
            await MainActor.run {
                contacts.removeAll { $0.id == id }
                LocalStorageManager.shared.removeContact(id: id)
                print("⚠️ ContactsService: Deleted contact locally only - \(id)")
            }
        }
    }

    func getContact(byId id: Int) async throws -> Contact? {
        if let contact = contacts.first(where: { $0.id == id }) {
            return contact
        }

        // Fetch from server if not in local cache
        await fetchContacts()
        return contacts.first(where: { $0.id == id })
    }

    func getAllContacts() async throws -> [Contact] {
        // Always return current contacts (may be from local storage)
        // Fetch from server in background if needed
        if contacts.isEmpty {
            await fetchContacts()
        }
        return contacts
    }

    private func updateOnlineStatuses() {
        let onlineUsers = SocketService.shared.onlineUsers

        for index in contacts.indices {
            contacts[index].isOnline = onlineUsers.contains(contacts[index].id)
        }
        print("🔵 ContactsService: Updated online statuses - \(onlineUsers.count) users online")
    }

    var favoriteContacts: [Contact] {
        contacts.filter { $0.isFavorite }.sorted { $0.displayName < $1.displayName }
    }

    var regularContacts: [Contact] {
        contacts.filter { !$0.isFavorite }.sorted { $0.displayName < $1.displayName }
    }

    var onlineContacts: [Contact] {
        contacts.filter { $0.isOnline }.sorted { $0.displayName < $1.displayName }
    }
}
