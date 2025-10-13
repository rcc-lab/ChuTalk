//
//  LocalStorageManager.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

class LocalStorageManager {
    static let shared = LocalStorageManager()

    private let contactsKey = "com.chutalk.localContacts"
    private let messagesKey = "com.chutalk.localMessages"
    private let userDefaults = UserDefaults.standard

    private init() {}

    // MARK: - Contacts

    func saveContacts(_ contacts: [Contact]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(contacts)
            userDefaults.set(data, forKey: contactsKey)
            print("✅ LocalStorage: Saved \(contacts.count) contacts")
        } catch {
            print("❌ LocalStorage: Failed to save contacts - \(error)")
        }
    }

    func loadContacts() -> [Contact] {
        guard let data = userDefaults.data(forKey: contactsKey) else {
            print("ℹ️ LocalStorage: No contacts found")
            return []
        }

        do {
            let decoder = JSONDecoder()
            let contacts = try decoder.decode([Contact].self, from: data)
            print("✅ LocalStorage: Loaded \(contacts.count) contacts")
            return contacts
        } catch {
            print("❌ LocalStorage: Failed to load contacts - \(error)")
            print("🧹 LocalStorage: Clearing old contact data")
            userDefaults.removeObject(forKey: contactsKey)
            return []
        }
    }

    func addContact(_ contact: Contact) {
        var contacts = loadContacts()

        // Check if contact already exists
        if contacts.contains(where: { $0.id == contact.id }) {
            print("⚠️ LocalStorage: Contact already exists")
            return
        }

        contacts.append(contact)
        saveContacts(contacts)
    }

    func removeContact(id: Int) {
        var contacts = loadContacts()
        contacts.removeAll { $0.id == id }
        saveContacts(contacts)
    }

    func updateContact(_ contact: Contact) {
        var contacts = loadContacts()

        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index] = contact
            saveContacts(contacts)
        }
    }

    func clearAllContacts() {
        userDefaults.removeObject(forKey: contactsKey)
        print("✅ LocalStorage: Cleared all contacts")
    }

    // MARK: - Messages

    func saveMessages(_ messages: [Message]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(messages)
            userDefaults.set(data, forKey: messagesKey)
            print("✅ LocalStorage: Saved \(messages.count) messages")
        } catch {
            print("❌ LocalStorage: Failed to save messages - \(error)")
        }
    }

    func loadMessages() -> [Message] {
        guard let data = userDefaults.data(forKey: messagesKey) else {
            print("ℹ️ LocalStorage: No messages found")
            return []
        }

        do {
            let decoder = JSONDecoder()
            let messages = try decoder.decode([Message].self, from: data)
            print("✅ LocalStorage: Loaded \(messages.count) messages")
            return messages
        } catch {
            print("❌ LocalStorage: Failed to load messages - \(error)")
            print("🧹 LocalStorage: Clearing old message data")
            userDefaults.removeObject(forKey: messagesKey)
            return []
        }
    }

    func addMessage(_ message: Message) {
        var messages = loadMessages()
        messages.append(message)
        saveMessages(messages)
    }

    func updateMessage(_ message: Message) {
        var messages = loadMessages()
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            saveMessages(messages)
        }
    }

    func getMessages(for userId: Int, currentUserId: Int) -> [Message] {
        let allMessages = loadMessages()
        return allMessages.filter {
            ($0.senderId == userId && $0.receiverId == currentUserId) ||
            ($0.senderId == currentUserId && $0.receiverId == userId)
        }.sorted { $0.timestamp < $1.timestamp }
    }

    func clearAllMessages() {
        userDefaults.removeObject(forKey: messagesKey)
        print("✅ LocalStorage: Cleared all messages")
    }
}
