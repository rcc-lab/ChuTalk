//
//  AuthService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine

class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authToken: String?

    private init() {
        checkAuthStatus()
    }

    func checkAuthStatus() {
        FileLogger.shared.log("checkAuthStatus() called", category: "AuthService")
        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken),
           let userIdString = KeychainManager.shared.get(key: Constants.Keychain.userId),
           let userId = Int(userIdString),
           let username = KeychainManager.shared.get(key: Constants.Keychain.username),
           let displayName = KeychainManager.shared.get(key: Constants.Keychain.displayName) {

            print("🔵 AuthService: Restoring auth state from keychain")
            FileLogger.shared.log("Restoring auth state from keychain for user \(userId)", category: "AuthService")
            self.authToken = token
            self.currentUser = User(id: userId, username: username, displayName: displayName, profileImageUrl: nil)
            self.isAuthenticated = true

            // Connect to socket on startup
            print("🔵 AuthService: Connecting to socket server on startup")
            FileLogger.shared.log("Connecting to socket server on startup", category: "AuthService")
            SocketService.shared.connect(userId: userId)

            // Re-upload device tokens after restoring auth state
            NotificationsService.shared.reuploadSavedTokens()
            print("✅ AuthService: Requested token reupload after restore")
            FileLogger.shared.log("✅ Requested token reupload after restore", category: "AuthService")
        } else {
            print("🔵 AuthService: No saved credentials found")
            FileLogger.shared.log("No saved credentials found", category: "AuthService")
            self.isAuthenticated = false
            self.currentUser = nil
            self.authToken = nil
        }
    }

    func register(username: String, password: String, displayName: String) async throws {
        let response = try await APIService.shared.register(
            username: username,
            password: password,
            displayName: displayName
        )

        if !response.ok {
            throw APIError.serverError(response.message ?? "Registration failed")
        }
    }

    func login(username: String, password: String) async throws {
        print("🔵 AuthService: Attempting login for \(username)")

        let response = try await APIService.shared.login(username: username, password: password)
        print("✅ AuthService: Received token from server")

        // Decode JWT token to get user info
        guard let payload = JWTDecoder.decode(token: response.token) else {
            print("❌ AuthService: Failed to decode JWT token")
            throw APIError.serverError("Failed to decode authentication token")
        }

        // Create user object from JWT payload
        let user = User(
            id: payload.uid,
            username: payload.u,
            displayName: payload.u, // Use username as display name initially
            profileImageUrl: nil
        )
        print("✅ AuthService: User extracted from JWT - id:\(user.id), username:\(user.username)")

        // Save credentials to keychain
        try KeychainManager.shared.save(key: Constants.Keychain.authToken, value: response.token)
        try KeychainManager.shared.save(key: Constants.Keychain.userId, value: String(user.id))
        try KeychainManager.shared.save(key: Constants.Keychain.username, value: user.username)
        try KeychainManager.shared.save(key: Constants.Keychain.displayName, value: user.displayName)
        try KeychainManager.shared.save(key: Constants.Keychain.password, value: password)  // 自動再ログイン用
        print("✅ AuthService: Credentials saved to keychain")

        // Update state
        await MainActor.run {
            self.authToken = response.token
            self.currentUser = user
            self.isAuthenticated = true
            print("✅ AuthService: State updated, isAuthenticated=true")
        }

        // Register with socket server
        SocketService.shared.connect(userId: user.id)
        print("✅ AuthService: Connected to socket server")

        // Re-upload device tokens (APNs and VoIP) after login
        NotificationsService.shared.reuploadSavedTokens()
        print("✅ AuthService: Requested token reupload")
    }

    func logout() {
        print("🔵 AuthService: Logout started")

        // Disconnect socket
        SocketService.shared.disconnect()
        print("✅ AuthService: Socket disconnected")

        // Clear keychain
        try? KeychainManager.shared.deleteAll()
        print("✅ AuthService: Keychain cleared")

        // Reset notification state (lastMessageIdなどをクリア)
        NotificationService.shared.resetNotificationState()
        print("✅ AuthService: Notification state reset")

        // Clear app badge
        MessagingService.shared.clearAppBadge()
        print("✅ AuthService: App badge cleared")

        // Update state on main thread
        Task { @MainActor in
            self.authToken = nil
            self.currentUser = nil
            self.isAuthenticated = false
            print("✅ AuthService: State cleared - isAuthenticated=\(self.isAuthenticated)")
        }
    }

    func autoLogin() async -> Bool {
        guard let token = KeychainManager.shared.get(key: Constants.Keychain.authToken),
              let userIdString = KeychainManager.shared.get(key: Constants.Keychain.userId),
              let userId = Int(userIdString),
              let username = KeychainManager.shared.get(key: Constants.Keychain.username),
              let displayName = KeychainManager.shared.get(key: Constants.Keychain.displayName) else {
            return false
        }

        // Set auth state
        await MainActor.run {
            self.authToken = token
            self.currentUser = User(id: userId, username: username, displayName: displayName, profileImageUrl: nil)
            self.isAuthenticated = true
        }

        // Connect to socket
        SocketService.shared.connect(userId: userId)

        return true
    }
}
