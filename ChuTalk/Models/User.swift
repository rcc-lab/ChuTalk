//
//  User.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
    }

    static func == (lhs: User, rhs: User) -> Bool {
        return lhs.id == rhs.id
    }
}

struct AuthResponse: Codable {
    let token: String
    let user: User?
}

// JWT Token payload
struct JWTPayload: Codable {
    let uid: Int
    let u: String
    let iat: Int
    let exp: Int
}

struct RegisterResponse: Codable {
    let ok: Bool
    let message: String?
}
