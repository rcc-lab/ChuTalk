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
    let callType: String? // "video" or "audio" from server

    enum CallType: String, Codable {
        case incoming
        case outgoing
        case missed
    }

    init(from decoder: Decoder) throws {
        print("📞 CallHistory: Starting decode...")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let extraContainer = try? decoder.container(keyedBy: ExtraCodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        print("📞 CallHistory: id = \(id)")

        // Get caller_id and callee_id to determine direction
        let callerId = try? extraContainer?.decode(Int.self, forKey: .callerId)
        let calleeId = try? container.decode(Int.self, forKey: .contactId)

        print("📞 CallHistory: callerId = \(String(describing: callerId)), calleeId = \(String(describing: calleeId))")

        // Get current user ID from AuthService
        let currentUserId = AuthService.shared.currentUser?.id ?? 0
        print("📞 CallHistory: currentUserId = \(currentUserId)")

        // Determine contactId and type based on caller/callee
        if let callerId = callerId, let calleeId = calleeId {
            if callerId == currentUserId {
                // I called someone (outgoing)
                contactId = calleeId
                type = .outgoing
                print("📞 CallHistory: Outgoing call to \(calleeId)")
            } else {
                // Someone called me (incoming)
                contactId = callerId
                type = .incoming
                print("📞 CallHistory: Incoming call from \(callerId)")
            }
        } else {
            // Fallback
            contactId = calleeId ?? 0
            type = .outgoing
            print("⚠️ CallHistory: Using fallback - contactId = \(contactId)")
        }

        // Get call_type (video/audio)
        callType = try? extraContainer?.decode(String.self, forKey: .callType)
        print("📞 CallHistory: callType = \(String(describing: callType))")

        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0

        // Try to decode timestamp from various fields
        if let timestampString = try? container.decode(String.self, forKey: .timestamp) {
            print("📞 CallHistory: Parsing timestamp string: '\(timestampString)'")

            // Try multiple formats
            var parsedDate: Date? = nil

            // Format 1: ISO8601 with microseconds "2025-10-15T00:32:32.968123"
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            parsedDate = iso8601Formatter.date(from: timestampString)

            if parsedDate == nil {
                // Format 2: ISO8601 without fractional seconds
                let iso8601Simple = ISO8601DateFormatter()
                iso8601Simple.formatOptions = [.withInternetDateTime]
                parsedDate = iso8601Simple.date(from: timestampString)
            }

            if parsedDate == nil {
                // Format 3: PostgreSQL raw format "2025-10-14 23:48:05.859231"
                let postgresFormatter = DateFormatter()
                postgresFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
                postgresFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                parsedDate = postgresFormatter.date(from: timestampString)
            }

            timestamp = parsedDate ?? Date()
            print("📞 CallHistory: Parsed timestamp: \(timestamp)")
        } else if let startedAt = try? extraContainer?.decode(String.self, forKey: .startedAt) {
            print("📞 CallHistory: Parsing started_at string: '\(startedAt)'")

            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = iso8601Formatter.date(from: startedAt) ?? Date()
        } else {
            print("⚠️ CallHistory: No timestamp found, using current date")
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
        case callerId = "caller_id"
        case callType = "call_type"
        case startedAt = "started_at"
    }

    init(id: Int, contactId: Int, type: CallType, duration: Int, timestamp: Date, contactName: String? = nil, callType: String? = nil) {
        self.id = id
        self.contactId = contactId
        self.type = type
        self.duration = duration
        self.timestamp = timestamp
        self.contactName = contactName
        self.callType = callType
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
