//
//  KeychainManager.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import KeychainSwift

class KeychainManager {
    static let shared = KeychainManager()

    private let keychain = KeychainSwift()

    private init() {}

    enum KeychainError: Error {
        case saveFailed
        case deleteFailed
        case itemNotFound
    }

    func save(key: String, value: String) throws {
        let success = keychain.set(value, forKey: key)
        if !success {
            throw KeychainError.saveFailed
        }
    }

    func get(key: String) -> String? {
        return keychain.get(key)
    }

    func delete(key: String) throws {
        let success = keychain.delete(key)
        if !success {
            throw KeychainError.deleteFailed
        }
    }

    func deleteAll() throws {
        let success = keychain.clear()
        if !success {
            throw KeychainError.deleteFailed
        }
    }
}
