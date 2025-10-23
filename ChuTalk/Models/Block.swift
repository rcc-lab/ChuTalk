//
//  Block.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct Block: Codable, Identifiable {
    let id: Int
    let blockerId: Int
    let blockedUserId: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case blockerId = "blocker_id"
        case blockedUserId = "blocked_user_id"
        case createdAt = "created_at"
    }
}

struct BlockResponse: Codable {
    let ok: Bool
    let message: String?
}
