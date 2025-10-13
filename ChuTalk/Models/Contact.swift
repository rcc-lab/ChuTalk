//
//  Contact.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct Contact: Codable, Identifiable, Equatable {
    let id: Int
    let username: String
    let displayName: String
    var isOnline: Bool
    var isFavorite: Bool

    init(id: Int, username: String, displayName: String, isOnline: Bool = false, isFavorite: Bool = false) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.isOnline = isOnline
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decode(String.self, forKey: .displayName)
        isOnline = try container.decodeIfPresent(Bool.self, forKey: .isOnline) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(isFavorite, forKey: .isFavorite)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case isOnline = "is_online"
        case isFavorite = "is_favorite"
    }

    static func == (lhs: Contact, rhs: Contact) -> Bool {
        return lhs.id == rhs.id
    }
}

struct AddContactResponse: Codable {
    let ok: Bool
    let contact: Contact?
}
