//
//  TurnCredentials.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct TurnCredentials: Codable {
    let username: String
    let credential: String
    let ttl: Int
    let urls: [String]

    enum CodingKeys: String, CodingKey {
        case username
        case credential
        case ttl
        case urls
    }
}
