//
//  Constants.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

struct Constants {
    // App Store Review Mode (App Store審査用の安全機能を有効化)
    // Set to true for App Store builds to enable v2 endpoints with blocking and content filtering
    // IMPORTANT: Set to false until v2 endpoints are fully tested
    static let isAppStoreReviewBuild = false  // Use v1 endpoints (original behavior)

    // Server Configuration
    struct Server {
        #if DEBUG
        // 開発・テスト環境（Debugビルド時）
        static let baseURL = "https://chutalk.ksc-sys.com"  // または別のテストサーバー
        #else
        // 本番環境（Releaseビルド時）
        static let baseURL = "https://chutalk.ksc-sys.com"
        #endif

        static let apiURL = "\(baseURL)/api"
        static let socketURL = baseURL
        static let socketPath = "/signal/socket.io/"
        static let stunServer = "stun:\(baseURL.replacingOccurrences(of: "https://", with: "")):3478"
        static let turnServer = "turn:\(baseURL.replacingOccurrences(of: "https://", with: "")):3478"
    }

    // API Endpoints
    struct API {
        static let register = "\(Server.apiURL)/auth/register"
        static let login = "\(Server.apiURL)/auth/login"
        static let turnCredentials = "\(Server.apiURL)/turn-cred"

        // v2 endpoints support blocking and content filtering for App Store compliance
        static let contacts = "\(Server.apiURL)/contacts\(Constants.isAppStoreReviewBuild ? ".v2" : "")"
        static let messages = "\(Server.apiURL)/messages\(Constants.isAppStoreReviewBuild ? ".v2" : "")"

        static let userSearch = "\(Server.apiURL)/users/search"
        static let calls = "\(Server.apiURL)/calls"
        static let callSignal = "\(Server.apiURL)/calls/signal"
        static let devices = "\(Server.apiURL)/me/devices"
    }

    // Socket Events
    struct SocketEvents {
        // Outgoing
        static let register = "register"
        static let offer = "offer"
        static let answer = "answer"
        static let ice = "ice"
        static let callEnd = "call-end"
        static let message = "message"

        // Incoming
        static let userOnline = "user-online"
        static let userOffline = "user-offline"
        static let incomingOffer = "offer"
        static let incomingAnswer = "answer"
        static let incomingIce = "ice"
        static let callEnded = "call-ended"
        static let messageReceived = "message"
    }

    // Keychain Keys
    struct Keychain {
        static let authToken = "com.chutalk.authToken"
        static let userId = "com.chutalk.userId"
        static let username = "com.chutalk.username"
        static let displayName = "com.chutalk.displayName"
        static let password = "com.chutalk.password"  // 自動再ログイン用
    }

    // UserDefaults Keys
    struct UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let preferredAudioDevice = "preferredAudioDevice"
        static let isVideoEnabledByDefault = "isVideoEnabledByDefault"
    }

    // Call Configuration
    struct Call {
        static let maxCallDuration: TimeInterval = 3600 // 1 hour
        static let connectionTimeout: TimeInterval = 30
        static let iceGatheringTimeout: TimeInterval = 10
    }

    // UI Configuration
    struct UI {
        static let animationDuration: Double = 0.3
        static let cornerRadius: CGFloat = 12
        static let standardPadding: CGFloat = 16
        static let smallPadding: CGFloat = 8
    }
}
