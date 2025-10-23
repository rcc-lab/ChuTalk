//
//  Message.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case video
}

struct Message: Codable, Identifiable, Equatable {
    let serverId: Int?
    let senderId: Int
    let receiverId: Int
    let content: String
    let timestamp: Date
    var isRead: Bool
    let messageType: MessageType
    let imageUrl: String?
    let videoUrl: String?

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
         isRead: Bool = false,
         messageType: MessageType = .text,
         imageUrl: String? = nil,
         videoUrl: String? = nil) {
        self.serverId = id
        self.senderId = senderId
        self.receiverId = receiverId
        self.content = content
        self.timestamp = timestamp
        self.isRead = isRead
        self.messageType = messageType
        self.imageUrl = imageUrl
        self.videoUrl = videoUrl
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

        // Decode message type, default to text if not present
        if let typeString = try? container.decode(String.self, forKey: .messageType),
           let type = MessageType(rawValue: typeString) {
            messageType = type
        } else {
            messageType = .text
        }

        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)

        // Try to decode timestamp from either "timestamp" or "created_at"
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            print("📅 Message: Decoding timestamp string: \(timestampString)")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: timestampString) {
                timestamp = date
                print("✅ Message: Successfully parsed timestamp: \(date)")
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                timestamp = formatter.date(from: timestampString) ?? Date()
                print("⚠️ Message: Fallback timestamp parsing, result: \(timestamp)")
            }
        } else if let createdAt = try? container.decode(String.self, forKey: .createdAt) {
            print("📅 Message: Decoding created_at string: \(createdAt)")
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: createdAt) {
                timestamp = date
                print("✅ Message: Successfully parsed created_at: \(date)")
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                timestamp = formatter.date(from: createdAt) ?? Date()
                print("⚠️ Message: Fallback created_at parsing, result: \(timestamp)")
            }
        } else if let timestampDate = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = timestampDate
            print("✅ Message: Decoded timestamp as Date: \(timestampDate)")
        } else {
            timestamp = Date()
            print("⚠️ Message: No timestamp found, using current date")
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
        try container.encode(messageType.rawValue, forKey: .messageType)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(videoUrl, forKey: .videoUrl)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case content = "body"
        case timestamp
        case createdAt = "created_at"
        case isRead = "is_read"
        case messageType = "message_type"
        case imageUrl = "image_url"
        case videoUrl = "video_url"
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
