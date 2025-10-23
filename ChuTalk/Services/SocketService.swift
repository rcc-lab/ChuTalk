//
//  SocketService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import SocketIO

class SocketService: ObservableObject {
    static let shared = SocketService()

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var currentUserId: Int?

    @Published var isConnected = false
    @Published var onlineUsers: Set<Int> = []

    // Callbacks - Call
    var onIncomingOffer: ((Int, String) -> Void)? // from, sdp
    var onIncomingAnswer: ((Int, String) -> Void)? // from, sdp
    var onIncomingIce: ((Int, [String: Any]) -> Void)? // from, candidate
    var onCallEnded: ((Int) -> Void)? // from

    // Callbacks - Messaging
    var onMessageReceived: ((Int, String, Date) -> Void)? // from, body, timestamp

    private init() {}

    func connect(userId: Int) {
        if manager != nil {
            print("⚠️ SocketService: Manager already exists, disconnecting first")
            FileLogger.shared.log("⚠️ Manager already exists, disconnecting first", category: "SocketService")
            disconnect()
        }

        guard let url = URL(string: Constants.Server.socketURL) else {
            print("❌ SocketService: Invalid socket URL")
            FileLogger.shared.log("❌ Invalid socket URL", category: "SocketService")
            return
        }

        print("🔵 SocketService: Connecting to \(url.absoluteString)")
        print("🔵 SocketService: User ID: \(userId)")
        print("🔵 SocketService: Path: /signal/socket.io/")
        FileLogger.shared.log("Connecting to \(url.absoluteString) for user \(userId)", category: "SocketService")

        // Store userId for registration on connect/reconnect
        self.currentUserId = userId

        manager = SocketManager(socketURL: url, config: [
            .log(true),
            .compress,
            .secure(true),
            .forceWebsockets(true),
            .path("/signal/socket.io/")
        ])

        socket = manager?.defaultSocket

        setupEventHandlers()

        socket?.connect()
        print("🔵 SocketService: Connection initiated")
        FileLogger.shared.log("Connection initiated", category: "SocketService")
    }

    func disconnect() {
        print("🔵 SocketService: Disconnecting...")
        socket?.disconnect()
        socket?.removeAllHandlers()
        socket = nil
        manager = nil
        currentUserId = nil
        isConnected = false
        onlineUsers.removeAll()
        print("✅ SocketService: Disconnected and cleaned up")
    }

    private func setupEventHandlers() {
        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            print("✅ SocketService: Socket connected - \(data)")
            FileLogger.shared.log("✅ Socket connected", category: "SocketService")
            self?.isConnected = true

            // Register user on every connect/reconnect
            if let userId = self?.currentUserId {
                print("🔵 SocketService: Auto-registering user on connect")
                FileLogger.shared.log("Auto-registering user \(userId) on connect", category: "SocketService")
                self?.registerUser(userId: userId)
            }
        }

        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            print("⚠️ SocketService: Socket disconnected - \(data)")
            FileLogger.shared.log("⚠️ Socket disconnected", category: "SocketService")
            self?.isConnected = false
        }

        socket?.on(clientEvent: .error) { data, ack in
            print("❌ SocketService: Socket error - \(data)")
            FileLogger.shared.log("❌ Socket error: \(data)", category: "SocketService")
        }

        socket?.on(clientEvent: .statusChange) { data, ack in
            print("🔵 SocketService: Status change - \(data)")
        }

        socket?.on(clientEvent: .reconnect) { data, ack in
            print("🔵 SocketService: Reconnecting - \(data)")
        }

        socket?.on(clientEvent: .reconnectAttempt) { data, ack in
            print("🔵 SocketService: Reconnect attempt - \(data)")
        }

        // WebSocket errors
        socket?.on(clientEvent: .websocketUpgrade) { data, ack in
            print("✅ SocketService: WebSocket upgraded - \(data)")
        }

        socket?.on(clientEvent: .ping) { data, ack in
            print("🔵 SocketService: Ping - \(data)")
        }

        socket?.on(clientEvent: .pong) { data, ack in
            print("🔵 SocketService: Pong - \(data)")
        }

        // Generic error catch
        socket?.onAny { event in
            print("🔵 SocketService: Event received - \(event.event): \(event.items ?? [])")
        }

        // User online/offline
        socket?.on(Constants.SocketEvents.userOnline) { [weak self] data, ack in
            print("🔵 SocketService: user-online event - \(data)")
            if let userData = data.first as? [String: Any],
               let userId = userData["userId"] as? Int {
                self?.onlineUsers.insert(userId)
                NotificationCenter.default.post(name: .userStatusChanged, object: nil)
                print("✅ SocketService: User \(userId) is now online")
            }
        }

        socket?.on(Constants.SocketEvents.userOffline) { [weak self] data, ack in
            print("🔵 SocketService: user-offline event - \(data)")
            if let userData = data.first as? [String: Any],
               let userId = userData["userId"] as? Int {
                self?.onlineUsers.remove(userId)
                NotificationCenter.default.post(name: .userStatusChanged, object: nil)
                print("✅ SocketService: User \(userId) is now offline")
            }
        }

        // Call events
        socket?.on(Constants.SocketEvents.incomingOffer) { [weak self] data, ack in
            print("🔵 SocketService: offer event - \(data)")
            if let offerData = data.first as? [String: Any],
               let from = offerData["from"] as? Int,
               let sdp = offerData["sdp"] as? String {
                self?.onIncomingOffer?(from, sdp)
                print("✅ SocketService: Received offer from \(from)")
            }
        }

        socket?.on(Constants.SocketEvents.incomingAnswer) { [weak self] data, ack in
            print("🔵 SocketService: answer event - \(data)")
            if let answerData = data.first as? [String: Any],
               let from = answerData["from"] as? Int,
               let sdp = answerData["sdp"] as? String {
                self?.onIncomingAnswer?(from, sdp)
                print("✅ SocketService: Received answer from \(from)")
            }
        }

        socket?.on(Constants.SocketEvents.incomingIce) { [weak self] data, ack in
            print("🔵 SocketService: ice event - \(data)")
            if let iceData = data.first as? [String: Any],
               let from = iceData["from"] as? Int,
               let candidate = iceData["candidate"] as? [String: Any] {
                self?.onIncomingIce?(from, candidate)
                print("✅ SocketService: Received ICE candidate from \(from)")
            }
        }

        socket?.on(Constants.SocketEvents.callEnded) { [weak self] data, ack in
            print("🔵 SocketService: call-ended event - \(data)")
            if let endData = data.first as? [String: Any],
               let from = endData["from"] as? Int {
                self?.onCallEnded?(from)
                print("✅ SocketService: Call ended from \(from)")
            }
        }

        // Message events
        socket?.on(Constants.SocketEvents.messageReceived) { [weak self] data, ack in
            print("🔵 SocketService: message event - \(data)")
            if let messageData = data.first as? [String: Any],
               let from = messageData["from"] as? Int,
               let body = messageData["body"] as? String {

                let timestamp: Date
                if let timestampString = messageData["timestamp"] as? String {
                    let dateFormatter = ISO8601DateFormatter()
                    timestamp = dateFormatter.date(from: timestampString) ?? Date()
                } else {
                    timestamp = Date()
                }

                self?.onMessageReceived?(from, body, timestamp)
                print("✅ SocketService: Received message from \(from)")
            }
        }
    }

    private func registerUser(userId: Int) {
        print("🔵 SocketService: Registering user - userId: \(userId)")
        socket?.emit(Constants.SocketEvents.register, [
            "userId": userId
        ])
        print("✅ SocketService: Registration message sent")
    }

    // MARK: - Call Signaling

    func sendOffer(to userId: Int, sdp: String, callId: String? = nil, hasVideo: Bool = true) {
        guard isConnected else {
            print("❌ SocketService: Cannot send offer - socket not connected")
            return
        }

        // Get current user's display name for VoIP push notifications
        let displayName = AuthService.shared.currentUser?.displayName ?? "Unknown"

        print("🔵 SocketService: Sending offer to \(userId)")
        var payload: [String: Any] = [
            "to": userId,
            "sdp": sdp,
            "displayName": displayName,
            "hasVideo": hasVideo
        ]

        // Add callId if provided (critical for VoIP Push)
        if let callId = callId {
            payload["callId"] = callId
            print("🔵 SocketService: Including callId: \(callId)")
        }

        socket?.emit(Constants.SocketEvents.offer, payload)
        print("✅ SocketService: Offer sent")
    }

    func sendAnswer(to userId: Int, sdp: String) {
        guard isConnected else {
            print("❌ SocketService: Cannot send answer - socket not connected")
            return
        }
        print("🔵 SocketService: Sending answer to \(userId)")
        socket?.emit(Constants.SocketEvents.answer, [
            "to": userId,
            "sdp": sdp
        ])
        print("✅ SocketService: Answer sent")
    }

    func sendIceCandidate(to userId: Int, candidate: [String: Any]) {
        guard isConnected else {
            print("❌ SocketService: Cannot send ICE candidate - socket not connected")
            return
        }
        print("🔵 SocketService: Sending ICE candidate to \(userId)")
        socket?.emit(Constants.SocketEvents.ice, [
            "to": userId,
            "candidate": candidate
        ])
    }

    func sendCallEnd(to userId: Int) {
        guard isConnected else {
            print("❌ SocketService: Cannot send call-end - socket not connected")
            return
        }
        print("🔵 SocketService: Sending call-end to \(userId)")
        socket?.emit(Constants.SocketEvents.callEnd, [
            "to": userId
        ])
        print("✅ SocketService: Call-end sent")
    }

    // MARK: - Messaging

    func sendMessage(to userId: Int, body: String) {
        guard isConnected else {
            print("❌ SocketService: Cannot send message - socket not connected")
            return
        }

        // Get current user's display name for push notifications
        let displayName = AuthService.shared.currentUser?.displayName ?? "Unknown"

        print("🔵 SocketService: Sending message to \(userId)")
        socket?.emit(Constants.SocketEvents.message, [
            "to": userId,
            "body": body,
            "displayName": displayName
        ])
        print("✅ SocketService: Message emit completed")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let userStatusChanged = Notification.Name("userStatusChanged")
}
