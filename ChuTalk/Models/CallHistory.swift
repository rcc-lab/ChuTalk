//
//  CallHistory.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct CallHistory: Codable, Identifiable, Equatable {
    let id: Int
    let contactId: Int
    let type: CallType
    let duration: Int // in seconds
    let timestamp: Date
    var contactName: String? // For display purposes

    enum CallType: String, Codable {
        case incoming
        case outgoing
        case missed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extraContainer = try? decoder.container(keyedBy: ExtraCodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        contactId = try container.decodeIfPresent(Int.self, forKey: .contactId) ?? 0

        // Try to decode call type from various fields
        if let typeString = try? container.decode(String.self, forKey: .type) {
            type = CallType(rawValue: typeString) ?? .outgoing
        } else if let callType = try? extraContainer?.decode(String.self, forKey: .callType) {
            type = CallType(rawValue: callType) ?? .outgoing
        } else {
            type = .outgoing
        }

        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0

        // Try to decode timestamp from various fields
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else if let startedAt = try? extraContainer?.decode(String.self, forKey: .startedAt) {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: startedAt) ?? Date()
        } else {
            timestamp = Date()
        }

        contactName = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(contactId, forKey: .contactId)
        try container.encode(type.rawValue, forKey: .type)
        try container.encode(duration, forKey: .duration)
        try container.encode(timestamp, forKey: .timestamp)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "callee_id"
        case type
        case duration
        case timestamp
    }

    private enum ExtraCodingKeys: String, CodingKey {
        case callType = "call_type"
        case startedAt = "started_at"
    }

    init(id: Int, contactId: Int, type: CallType, duration: Int, timestamp: Date, contactName: String? = nil) {
        self.id = id
        self.contactId = contactId
        self.type = type
        self.duration = duration
        self.timestamp = timestamp
        self.contactName = contactName
    }

    static func == (lhs: CallHistory, rhs: CallHistory) -> Bool {
        return lhs.id == rhs.id
    }

    var durationString: String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
