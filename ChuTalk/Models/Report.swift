//
//  Report.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct Report: Codable, Identifiable {
    let id: Int
    let reporterId: Int
    let reportedUserId: Int
    let messageId: Int?
    let reason: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case reporterId = "reporter_id"
        case reportedUserId = "reported_user_id"
        case messageId = "message_id"
        case reason
        case status
        case createdAt = "created_at"
    }
}

struct ReportRequest: Codable {
    let reportedUserId: Int
    let messageId: Int?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reportedUserId = "reported_user_id"
        case messageId = "message_id"
        case reason
    }
}

struct ActionResponse: Codable {
    let ok: Bool
    let message: String?
}

// Legacy alias for compatibility
typealias ReportResponse = ActionResponse
