//
//  Message.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct Message: Codable, Identifiable, Equatable {
    let serverId: Int?
    let senderId: Int
    let receiverId: Int
    let content: String
    let timestamp: Date
    var isRead: Bool

    // Computed property for Identifiable
    var id: String {
        if let serverId = serverId {
            return "server-\(serverId)"
        } else {
            return "local-\(senderId)-\(receiverId)-\(timestamp.timeIntervalSince1970)"
        }
    }

    var isSentByCurrentUser: Bool {
        senderId == AuthService.shared.currentUser?.id
    }

    init(id: Int? = nil,
         senderId: Int,
         receiverId: Int,
         content: String,
         timestamp: Date = Date(),
         isRead: Bool = false) {
        self.serverId = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
    }

    static func == (lhs: Message, rhs: Message) -> Bool {
        return lhs.id == rhs.id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverId = try container.decodeIfPresent(Int.self, forKey: .id)
        senderId = try container.decode(Int.self, forKey: .senderId)
        receiverId = try container.decode(Int.self, forKey: .receiverId)
        content = try container.decode(String.self, forKey: .content)
        isRead = try container.decode(Bool.self, forKey: .isRead)

        // Try to decode timestamp from either "timestamp" or "created_at"
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else if let createdAt = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: createdAt) ?? Date()
        } else if let timestampDate = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = timestampDate
        } else {
            timestamp = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(serverId, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(receiverId, forKey: .receiverId)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case content = "body"
        case timestamp
        case createdAt = "created_at"
        case isRead = "is_read"
    }
}

struct Conversation: Identifiable {
    let id: Int
    let contact: Contact
    var messages: [Message]
    var lastMessage: Message? {
        messages.sorted { $0.timestamp > $1.timestamp }.first
    }
    var unreadCount: Int {
        messages.filter { !$0.isRead && !$0.isSentByCurrentUser }.count
    }
}
