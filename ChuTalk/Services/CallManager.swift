//
//  CallManager.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import WebRTC
import Combine
import AVFoundation

enum CallState {
    case idle
    case ringing
    case connecting
    case connected
    case ended
}

enum CallDirection {
    case incoming
    case outgoing
}

class CallManager: ObservableObject {
    static let shared = CallManager()

    @Published var callState: CallState = .idle
    @Published var currentContact: Contact?
    @Published var callDirection: CallDirection?
    @Published var callDuration: TimeInterval = 0
    @Published var isVideoCall: Bool = true
    @Published var showIncomingCallView: Bool = false
    @Published var showActiveCallView: Bool = false
    @Published var hasIncomingCall: Bool = false
    @Published var incomingCallerId: Int?
    @Published var incomingOffer: String?

    private var callTimer: Timer?
    private var callStartTime: Date?
    private var pendingIceCandidates: [[String: Any]] = []
    var callId: String?
    var callUUID: UUID?  // CallKit用のUUID
    private var incomingCallTimer: Timer?
    private var answerReceived: Bool = false  // answer重複処理を防ぐフラグ
    private var isSettingUpCall: Bool = false  // 通話セットアップ中フラグ（切断ループ防止）
    private var ringbackTimer: Timer?  // 呼び出し音タイマー

    private let webRTCService = WebRTCService.shared
    private let socketService = SocketService.shared
    private let audioManager = AudioManager.shared

    private init() {
        setupSocketCallbacks()
        setupWebRTCCallbacks()
        setupCallKitNotifications()
    }

    private func setupCallKitNotifications() {
        // CallKit応答通知を購読
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCallKitAnswer(_:)),
            name: .callKitAnswerCall,
            object: nil
        )
    }

    @objc private func handleCallKitAnswer(_ notification: Notification) {
        print("📞 CallManager: ========== RECEIVED CALLKIT ANSWER NOTIFICATION ==========")
        FileLogger.shared.log("========== RECEIVED CALLKIT ANSWER NOTIFICATION ==========", category: "CallManager")

        guard let userInfo = notification.userInfo,
              let callUUID = userInfo["callUUID"] as? String,
              let callId = userInfo["callId"] as? String,
              let callerId = userInfo["callerId"] as? Int,
              let callerName = userInfo["callerName"] as? String,
              let hasVideo = userInfo["hasVideo"] as? Bool else {
            print("❌ CallManager: Invalid notification userInfo")
            FileLogger.shared.log("❌ Invalid notification userInfo", category: "CallManager")
            return
        }

        // VoIP Push経由でofferが含まれている場合は取得
        let offerFromPush = userInfo["offer"] as? String

        print("📞 CallManager: User accepted call via CallKit")
        print("   Call UUID: \(callUUID)")
        print("   Call ID: \(callId)")
        print("   Caller ID: \(callerId)")
        print("   Caller Name: \(callerName)")
        print("   Has Video: \(hasVideo)")
        print("   Offer from Push: \(offerFromPush != nil ? "YES (\(offerFromPush!.count) chars)" : "NO")")

        FileLogger.shared.log("User accepted call via CallKit - UUID:\(callUUID) ID:\(callId) Caller:\(callerId)(\(callerName)) Video:\(hasVideo) Offer:\(offerFromPush != nil ? "YES" : "NO")", category: "CallManager")

        Task { @MainActor in
            // CallManagerの状態を設定（VoIP Push経由の場合に必要）
            print("🔧 CallManager: Setting up state from CallKit notification...")
            FileLogger.shared.log("Setting up state from CallKit notification", category: "CallManager")

            // アプリ完全停止状態から起動した場合、サービスの初期化待機
            print("⏳ CallManager: Waiting for services initialization (1 second)...")
            FileLogger.shared.log("⏳ Waiting for services initialization (1 second)", category: "CallManager")

            // Wait 1 second for services to fully initialize
            // Camera will start asynchronously when CallKit audio session is activated
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            print("✅ CallManager: Initialization complete")
            FileLogger.shared.log("✅ Initialization complete", category: "CallManager")

            self.callId = callId
            self.callUUID = UUID(uuidString: callUUID)
            self.isVideoCall = hasVideo
            self.callDirection = .incoming
            self.callState = .connecting
            self.showActiveCallView = true  // 🔑 通話画面を表示（VoIP Push経由で重要）

            print("✅ CallManager: Set showActiveCallView = true")
            print("✅ CallManager: Video mode: \(hasVideo ? "ビデオ通話" : "音声通話")")

            // ContactsServiceから連絡先を取得
            do {
                print("🔧 CallManager: Fetching contact for callerId: \(callerId)...")
                FileLogger.shared.log("Fetching contact for callerId: \(callerId)", category: "CallManager")
                if let contact = try await ContactsService.shared.getContact(byId: callerId) {
                    self.currentContact = contact
                    print("✅ CallManager: Contact set: \(contact.displayName)")
                    FileLogger.shared.log("✅ Contact set: \(contact.displayName)", category: "CallManager")
                } else {
                    print("⚠️ CallManager: Contact not found, creating temporary contact")
                    FileLogger.shared.log("⚠️ Contact not found, creating temporary contact", category: "CallManager")
                    // 連絡先が見つからない場合は一時的な連絡先を作成
                    self.currentContact = Contact(
                        id: callerId,
                        username: "user\(callerId)",
                        displayName: callerName,
                        isOnline: false,
                        isFavorite: false
                    )
                }

                // Offerの取得（VoIP Pushに含まれていればそれを使用、なければAPIから取得）
                var offerSDP: String? = offerFromPush
                let maxRetries = 10  // 最大10回リトライ (約20秒)

                if offerSDP != nil {
                    print("✅ CallManager: Using offer from VoIP Push payload")
                    FileLogger.shared.log("✅ Using offer from VoIP Push payload, length: \(offerSDP!.count)", category: "CallManager")
                } else {
                    // APIからofferを取得（リトライロジック追加）
                    print("🔧 CallManager: Fetching offer from API for callId: \(callId)...")
                    FileLogger.shared.log("Fetching offer from API for callId: \(callId)", category: "CallManager")

                    let retryInterval: UInt64 = 2_000_000_000  // 2秒待機

                    for attempt in 1...maxRetries {
                        print("🔄 CallManager: Attempt \(attempt)/\(maxRetries) to fetch offer...")
                        FileLogger.shared.log("🔄 Attempt \(attempt)/\(maxRetries) to fetch offer", category: "CallManager")

                        offerSDP = try await APIService.shared.getOfferSDP(callId: callId)

                        if offerSDP != nil {
                            print("✅ CallManager: Offer retrieved on attempt \(attempt), length: \(offerSDP!.count)")
                            FileLogger.shared.log("✅ Offer retrieved on attempt \(attempt), length: \(offerSDP!.count)", category: "CallManager")
                            break
                        }

                        if attempt < maxRetries {
                            print("⚠️ CallManager: Offer not found, waiting 2 seconds before retry...")
                            FileLogger.shared.log("⚠️ Offer not found, waiting 2 seconds before retry (attempt \(attempt)/\(maxRetries))", category: "CallManager")
                            try await Task.sleep(nanoseconds: retryInterval)  // 2秒待機
                        }
                    }
                }

                if let offerSDP = offerSDP {
                    self.incomingOffer = offerSDP
                    FileLogger.shared.log("Starting acceptIncomingCall()", category: "CallManager")

                    // acceptIncomingCall()を呼び出し
                    await self.acceptIncomingCall()
                } else {
                    print("❌ CallManager: No offer found after \(maxRetries) attempts for callId: \(callId)")
                    print("❌ CallManager: Ending call due to missing offer")
                    FileLogger.shared.log("❌ No offer found after \(maxRetries) attempts, ending call", category: "CallManager")
                    await self.endCall()
                }
            } catch {
                print("❌ CallManager: Error setting up state: \(error)")
                FileLogger.shared.log("❌ Error setting up state: \(error.localizedDescription)", category: "CallManager")
            }
        }
    }

    private func generateCallId(myId: Int, otherId: Int) -> String {
        // callIdの形式: "発信者ID-着信者ID"
        // myId = 発信者（自分）、otherId = 着信者（相手）
        return "\(myId)-\(otherId)"
    }

    private func setupSocketCallbacks() {
        // Incoming offer (call request)
        socketService.onIncomingOffer = { [weak self] fromUserId, sdp in
            Task { @MainActor in
                await self?.handleIncomingOffer(from: fromUserId, sdp: sdp)
            }
        }

        // Incoming answer (call accepted)
        socketService.onIncomingAnswer = { [weak self] fromUserId, sdp in
            Task { @MainActor in
                await self?.handleIncomingAnswer(sdp: sdp)
            }
        }

        // Incoming ICE candidate
        socketService.onIncomingIce = { [weak self] fromUserId, candidate in
            self?.handleRemoteIceCandidate(candidate: candidate)
        }

        // Call ended
        socketService.onCallEnded = { [weak self] fromUserId in
            Task { @MainActor in
                await self?.endCall()
            }
        }
    }

    private func setupWebRTCCallbacks() {
        webRTCService.onIceCandidate = { [weak self] candidate in
            guard let self = self,
                  let contact = self.currentContact else {
                print("⚠️ CallManager: onIceCandidate - no self or contact")
                FileLogger.shared.log("⚠️ onIceCandidate - no self or contact", category: "CallManager")
                return
            }

            let candidateDict: [String: Any] = [
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": Int32(candidate.sdpMLineIndex),
                "candidate": candidate.sdp
            ]

            // Add small delay before sending to allow batching of multiple candidates
            // This helps iPhone 12 Pro collect all candidates before sending
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms delay

                // Send ICE candidate via Socket.io
                self.socketService.sendIceCandidate(to: contact.id, candidate: candidateDict)
                print("✅ CallManager: Sent ICE candidate via Socket.io to user \(contact.id)")
                FileLogger.shared.log("✅ Sent ICE candidate to user \(contact.id), mid: \(candidate.sdpMid ?? "nil"), index: \(candidate.sdpMLineIndex)", category: "CallManager")
            }
        }

        webRTCService.onConnected = { [weak self] in
            print("🔔 CallManager: onConnected callback triggered!")
            Task { @MainActor in
                print("🔔 CallManager: onConnected - inside MainActor block")
                print("🔔 CallManager: Current call state: \(String(describing: self?.callState))")
                self?.callState = .connected
                self?.startCallTimer()
                self?.stopRingbackTone()  // 呼び出し音を停止
                self?.isSettingUpCall = false  // セットアップ完了（ICE接続成功）
                print("✅ CallManager: Call connected - setup complete")
            }
        }

        webRTCService.onDisconnected = { [weak self] in
            Task { @MainActor in
                // セットアップ中は切断コールバックを無視（無限ループ防止）
                guard let self = self, !self.isSettingUpCall else {
                    print("⚠️ CallManager: Ignoring disconnect during setup")
                    return
                }
                print("🔵 CallManager: Disconnect callback triggered")
                await self.endCall()
            }
        }
    }

    // MARK: - Public Methods

    @MainActor
    func startCall(to contact: Contact, isVideo: Bool) async {
        print("🔵 CallManager: Starting call to \(contact.displayName)")
        FileLogger.shared.log("========== STARTING OUTGOING CALL ==========", category: "CallManager")
        FileLogger.shared.log("🔵 Starting call to \(contact.displayName), isVideo: \(isVideo)", category: "CallManager")

        guard let currentUserId = AuthService.shared.currentUser?.id else {
            print("❌ CallManager: No current user")
            FileLogger.shared.log("❌ No current user", category: "CallManager")
            return
        }

        self.isSettingUpCall = true  // セットアップ開始
        self.currentContact = contact
        self.isVideoCall = isVideo
        self.callDirection = .outgoing
        self.callState = .connecting
        self.answerReceived = false  // Reset flag

        // Generate call ID and UUID
        self.callId = generateCallId(myId: currentUserId, otherId: contact.id)
        self.callUUID = UUID()
        print("🔵 CallManager: Call ID: \(self.callId!)")
        print("🔵 CallManager: Call UUID: \(self.callUUID!)")
        FileLogger.shared.log("🔵 Call ID: \(self.callId!), UUID: \(self.callUUID!)", category: "CallManager")

        // CallKitで発信を開始
        CallKitProvider.shared.startOutgoingCall(
            uuid: callUUID!,
            to: contact.displayName,
            contactId: contact.id,
            hasVideo: isVideo,
            callId: callId!
        )
        FileLogger.shared.log("✅ CallKit outgoing call started", category: "CallManager")

        // Configure audio session
        print("🔊 CallManager: Configuring audio session for outgoing call...")
        FileLogger.shared.log("🔊 Configuring audio session for outgoing call", category: "CallManager")
        audioManager.configureForCall()
        print("✅ CallManager: Audio session configured for outgoing call")
        FileLogger.shared.log("✅ Audio session configured for outgoing call", category: "CallManager")

        // Setup WebRTC
        do {
            FileLogger.shared.log("Step 1 - Setting up peer connection", category: "CallManager")
            try await setupPeerConnection()
            FileLogger.shared.log("✅ Step 1 - Peer connection setup complete", category: "CallManager")

            // Camera starts asynchronously in background - don't wait
            // Proceed immediately to create offer for fast call setup
            if isVideo {
                print("ℹ️ CallManager: Video call - camera starting in background")
                FileLogger.shared.log("ℹ️ Video call - camera starting in background", category: "CallManager")
            }

            // Create offer
            FileLogger.shared.log("Step 2 - Creating offer", category: "CallManager")
            let offer = try await webRTCService.createOffer(isVideo: isVideo)
            FileLogger.shared.log("✅ Step 2 - Offer created, SDP length: \(offer.sdp.count)", category: "CallManager")

            // CRITICAL: Save offer to API FIRST (before Socket.io)
            // This ensures the offer is available when the callee answers via CallKit
            FileLogger.shared.log("Step 3 - Saving offer to API", category: "CallManager")
            do {
                try await APIService.shared.sendSignal(
                    callId: callId!,
                    action: "offer",
                    data: ["sdp": offer.sdp, "type": "offer"]
                )
                print("✅ CallManager: Offer saved to API for callId: \(callId!)")
                FileLogger.shared.log("✅ Step 3 - Offer saved to API", category: "CallManager")
            } catch {
                print("❌ CallManager: CRITICAL - Failed to save offer to API - \(error)")
                FileLogger.shared.log("❌ CRITICAL - Failed to save offer to API: \(error)", category: "CallManager")
                // Continue anyway, Socket.io might still work
            }

            // Send offer via Socket.io (for online callees)
            // CRITICAL: Include callId and hasVideo for VoIP Push
            FileLogger.shared.log("Step 4 - Sending offer via Socket.io with callId: \(callId!)", category: "CallManager")
            socketService.sendOffer(to: contact.id, sdp: offer.sdp, callId: callId!, hasVideo: isVideo)
            FileLogger.shared.log("✅ Step 4 - Offer sent via Socket.io", category: "CallManager")

            // Show call view
            self.showActiveCallView = true

            // Start ringback tone (呼び出し音)
            self.startRingbackTone()

            // Note: isSettingUpCallはonConnectedコールバックでfalseに設定される

            print("✅ CallManager: Offer sent via Socket.io to \(contact.displayName)")
            FileLogger.shared.log("✅ ========== Outgoing call setup COMPLETE ==========", category: "CallManager")

            // Start polling for answer from API (fallback if Socket.IO doesn't deliver)
            Task {
                await pollForAnswer()
            }

            // Record call in history
            Task {
                do {
                    _ = try await APIService.shared.recordCall(
                        calleeId: contact.id,
                        callType: isVideo ? "video" : "audio"
                    )
                } catch {
                    print("⚠️ CallManager: Failed to record call - \(error)")
                }
            }
        } catch {
            print("❌ CallManager: Failed to start call - \(error)")
            FileLogger.shared.log("❌ Failed to start call: \(error)", category: "CallManager")
            self.isSettingUpCall = false  // エラー時もフラグをクリア
            await endCall()
        }
    }

    private func pollForAnswer() async {
        guard let callId = self.callId else { return }

        // Wait a bit for Socket.IO answer first
        try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

        // Poll for up to 15 seconds
        for attempt in 1...15 {
            // Check if we already received answer
            guard await MainActor.run(body: {
                self.callState == .connecting && self.callDirection == .outgoing && !self.answerReceived
            }) else {
                print("✅ CallManager: Answer already received, stopping API polling")
                return
            }

            print("🔍 CallManager: Polling API for answer (attempt \(attempt)/15)...")

            do {
                if let answerSDP = try await APIService.shared.getAnswerSDP(callId: callId) {
                    print("✅ CallManager: Found answer in API! Processing...")
                    await handleIncomingAnswer(sdp: answerSDP)
                    return
                }
            } catch {
                print("⚠️ CallManager: Error polling for answer - \(error)")
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        print("⚠️ CallManager: No answer received after 18 seconds (3s wait + 15s polling)")
    }

    @MainActor
    func acceptCall() async {
        guard callDirection == .incoming,
              let contact = currentContact else {
            print("❌ CallManager: Cannot accept call - no incoming call")
            return
        }

        print("🔵 CallManager: Accepting call from \(contact.displayName)")

        callState = .connecting
        showIncomingCallView = false
        showActiveCallView = true

        // Configure audio (CallKitを使用時はCallKitが管理)
        // audioManager.configureForCall()

        do {
            // Create answer
            let answer = try await webRTCService.createAnswer(isVideo: isVideoCall)

            // Send answer via Socket.io
            socketService.sendAnswer(to: contact.id, sdp: answer.sdp)
            print("✅ CallManager: Answer sent via Socket.io to \(contact.displayName)")

            // Add pending ICE candidates
            for candidateDict in pendingIceCandidates {
                handleRemoteIceCandidate(candidate: candidateDict)
            }
            pendingIceCandidates.removeAll()
        } catch {
            print("❌ CallManager: Failed to accept call - \(error)")
            await endCall()
        }
    }

    @MainActor
    func rejectCall() async {
        guard let contact = currentContact else { return }

        print("🔵 CallManager: Rejecting call from \(contact.displayName)")

        socketService.sendCallEnd(to: contact.id)

        showIncomingCallView = false
        currentContact = nil
        callDirection = nil
        callState = .idle

        webRTCService.disconnect()
    }

    @MainActor
    func endCall() async {
        print("🔵 CallManager: Ending call")

        // callIdを保存（後でクリアに使用）
        let callIdToClean = callId

        // CallKitに通話終了を通知
        if let uuid = callUUID {
            print("🔵 CallManager: Notifying CallKit to end call - UUID: \(uuid)")
            CallKitProvider.shared.endCall(uuid: uuid)
        }

        if let contact = currentContact {
            socketService.sendCallEnd(to: contact.id)
        }

        stopCallTimer()
        stopRingbackTone()  // 呼び出し音を停止

        callState = .ended
        showActiveCallView = false
        showIncomingCallView = false

        // Cleanup
        webRTCService.disconnect()
        audioManager.configureForEndCall()

        // Clear processedCallIds
        if let callIdToClean = callIdToClean {
            print("🔵 CallManager: Clearing processedCallId: \(callIdToClean)")
            NotificationService.shared.clearProcessedCallId(callIdToClean)
        }

        // Reset state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.callState = .idle
            self?.currentContact = nil
            self?.callDirection = nil
            self?.callDuration = 0
            self?.callId = nil
            self?.callUUID = nil
            self?.answerReceived = false
            self?.isSettingUpCall = false  // フラグをリセット
        }
    }

    func toggleMute() {
        webRTCService.toggleMute()
    }

    func toggleVideo() {
        webRTCService.toggleVideo()
    }

    func toggleCamera() {
        webRTCService.switchCamera()
    }

    func toggleSpeaker() {
        audioManager.toggleSpeaker()
    }

    // MARK: - Incoming Call Detection

    // 着信監視はNotificationServiceに移行したため、この関数は互換性のために残す
    func startListeningForIncomingCalls(userId: Int) {
        print("ℹ️ CallManager: Incoming call monitoring is now handled by NotificationService")
    }

    func stopListeningForIncomingCalls() {
        print("ℹ️ CallManager: Incoming call monitoring is now handled by NotificationService")
    }

    @MainActor
    func acceptIncomingCall() async {
        print("🔵 CallManager: ========== acceptIncomingCall() START ==========")
        FileLogger.shared.log("========== acceptIncomingCall() START ==========", category: "CallManager")
        print("🔵 CallManager: incomingOffer exists: \(incomingOffer != nil)")
        print("🔵 CallManager: currentContact exists: \(currentContact != nil)")

        guard let offer = incomingOffer,
              let contact = currentContact else {
            print("❌ CallManager: Cannot accept call - missing offer or contact")
            FileLogger.shared.log("❌ Cannot accept call - missing offer or contact", category: "CallManager")
            print("❌ CallManager: incomingOffer: \(String(describing: incomingOffer?.prefix(100)))")
            print("❌ CallManager: currentContact: \(String(describing: currentContact))")
            return
        }

        print("🔵 CallManager: Accepting incoming call from \(contact.displayName)")
        print("🔵 CallManager: Offer SDP length: \(offer.count)")
        FileLogger.shared.log("Accepting incoming call from \(contact.displayName), offer length: \(offer.count)", category: "CallManager")

        self.isSettingUpCall = true  // セットアップ開始

        // callUUIDが設定されている場合はCallKit経由なので、isVideoCallを維持
        // そうでない場合はSDPから判別
        if self.callUUID == nil {
            let hasVideo = detectVideoFromSDP(offer)
            self.isVideoCall = hasVideo
            print("🔵 CallManager: Call type from SDP: \(hasVideo ? "ビデオ通話" : "音声通話")")
        } else {
            print("🔵 CallManager: Using CallKit video flag: \(self.isVideoCall ? "ビデオ通話" : "音声通話")")
        }

        hasIncomingCall = false
        callState = .connecting
        callDirection = .incoming
        showActiveCallView = true

        // Configure audio session
        print("🔊 CallManager: Configuring audio session...")
        FileLogger.shared.log("🔊 Configuring audio session", category: "CallManager")
        audioManager.configureForCall()
        print("✅ CallManager: Audio session configured")
        FileLogger.shared.log("✅ Audio session configured", category: "CallManager")

        do {
            print("🔧 CallManager: Step 1 - Setting up peer connection...")
            FileLogger.shared.log("Step 1 - Setting up peer connection", category: "CallManager")
            // Setup peer connection
            try await setupPeerConnection()
            print("✅ CallManager: Step 1 - Peer connection setup complete")
            FileLogger.shared.log("✅ Step 1 - Peer connection setup complete", category: "CallManager")

            print("🔧 CallManager: Step 2 - Setting remote description (offer)...")
            FileLogger.shared.log("Step 2 - Setting remote description (offer)", category: "CallManager")
            // Set remote description (offer)
            try await webRTCService.setRemoteDescription(sdp: offer, type: .offer)
            print("✅ CallManager: Step 2 - Remote description set")
            FileLogger.shared.log("✅ Step 2 - Remote description set", category: "CallManager")

            // Camera will start asynchronously in background
            // Wait briefly for camera to start sending frames (critical for video ICE candidates)
            if isVideoCall {
                print("ℹ️ CallManager: Video call - waiting 0.5s for camera frames...")
                FileLogger.shared.log("ℹ️ Video call - waiting 0.5s for camera frames", category: "CallManager")
                try await Task.sleep(nanoseconds: 500_000_000)  // 500ms wait for camera frames
                print("✅ CallManager: Camera wait complete, proceeding with answer")
                FileLogger.shared.log("✅ Camera wait complete", category: "CallManager")
            }

            print("🔧 CallManager: Step 3 - Creating answer...")
            FileLogger.shared.log("Step 3 - Creating answer", category: "CallManager")
            // Create answer
            let answer = try await webRTCService.createAnswer(isVideo: isVideoCall)
            print("✅ CallManager: Step 3 - Answer created, SDP length: \(answer.sdp.count)")
            FileLogger.shared.log("✅ Step 3 - Answer created, SDP length: \(answer.sdp.count)", category: "CallManager")

            print("🔧 CallManager: Step 4 - Sending answer via Socket.io...")
            print("🔍 CallManager: Socket.io connected: \(socketService.isConnected)")
            FileLogger.shared.log("Step 4 - Socket.io connected: \(socketService.isConnected)", category: "CallManager")

            // Socket.io接続待ち（最大3秒）
            if !socketService.isConnected {
                print("⚠️ CallManager: Socket.io not connected, waiting up to 3 seconds...")
                FileLogger.shared.log("⚠️ Socket.io not connected, waiting up to 3 seconds", category: "CallManager")
                var waitCount = 0
                while !socketService.isConnected && waitCount < 30 {
                    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒
                    waitCount += 1
                }
                print("🔍 CallManager: After waiting, Socket.io connected: \(socketService.isConnected)")
                FileLogger.shared.log("After waiting, Socket.io connected: \(socketService.isConnected)", category: "CallManager")
            }

            // CRITICAL: Save answer to API FIRST before Socket.IO
            // This ensures the caller can retrieve it via polling if Socket.IO fails
            if let myUserId = AuthService.shared.currentUser?.id,
               let callId = self.callId {
                do {
                    print("🔧 CallManager: Step 5 - Saving answer to API (priority delivery)...")
                    FileLogger.shared.log("Step 5 - Saving answer to API (priority delivery)", category: "CallManager")
                    try await APIService.shared.saveAnswer(callId: callId, sdp: answer.sdp, from: myUserId, to: contact.id)
                    print("✅ CallManager: Answer saved to API for callId: \(callId)")
                    FileLogger.shared.log("✅ Answer saved to API for callId: \(callId)", category: "CallManager")
                } catch {
                    print("⚠️ CallManager: Failed to save answer to API - \(error) (continuing anyway)")
                    FileLogger.shared.log("⚠️ Failed to save answer to API: \(error.localizedDescription)", category: "CallManager")
                }
            }

            // Then send via Socket.io (if connected) - this is fast but may fail if not connected yet
            socketService.sendAnswer(to: contact.id, sdp: answer.sdp)
            print("✅ CallManager: Answer sent via Socket.io to user \(contact.id) (connected: \(socketService.isConnected))")
            FileLogger.shared.log("✅ Answer sent via Socket.io to user \(contact.id) (connected: \(socketService.isConnected))", category: "CallManager")

            // Additional Socket.IO retry after 1 second to ensure delivery
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // Wait 1 second
                if self.socketService.isConnected {
                    self.socketService.sendAnswer(to: contact.id, sdp: answer.sdp)
                    print("✅ CallManager: Answer re-sent via Socket.io (retry) to user \(contact.id)")
                    FileLogger.shared.log("✅ Answer re-sent via Socket.io (retry)", category: "CallManager")
                }
            }

            print("🔧 CallManager: Step 6 - Adding pending ICE candidates (\(pendingIceCandidates.count))...")
            // Add pending ICE candidates
            for candidateDict in pendingIceCandidates {
                handleRemoteIceCandidate(candidate: candidateDict)
            }
            pendingIceCandidates.removeAll()

            // Note: isSettingUpCallはonConnectedコールバックでfalseに設定される（ICE接続成功まで待つ）

            print("✅ CallManager: ========== Incoming call accepted COMPLETE ==========")
            FileLogger.shared.log("✅ ========== Incoming call accepted COMPLETE ==========", category: "CallManager")
        } catch {
            print("❌ CallManager: ========== FAILED to accept call ==========")
            print("❌ CallManager: Error type: \(type(of: error))")
            print("❌ CallManager: Error: \(error)")
            print("❌ CallManager: Error localizedDescription: \(error.localizedDescription)")
            FileLogger.shared.log("❌ ========== FAILED to accept call: \(error.localizedDescription) ==========", category: "CallManager")
            self.isSettingUpCall = false  // エラー時もフラグをクリア
            await endCall()
        }
    }

    @MainActor
    func declineIncomingCall() {
        print("🔵 CallManager: Declining incoming call")

        // callIdを保存してクリア
        if let callIdToClean = callId {
            NotificationService.shared.clearProcessedCallId(callIdToClean)
        }

        hasIncomingCall = false
        incomingCallerId = nil
        incomingOffer = nil
        currentContact = nil
        callId = nil
    }

    // MARK: - Private Methods

    private func setupPeerConnection() async throws {
        // Get TURN credentials
        print("🔧 CallManager: Fetching TURN credentials from API...")
        let turnCredentials = try await APIService.shared.getTurnCredentials()
        print("✅ CallManager: TURN credentials received")
        print("   Username: \(turnCredentials.username)")
        print("   URLs count: \(turnCredentials.urls.count)")
        for (index, url) in turnCredentials.urls.enumerated() {
            print("   URL[\(index)]: \(url)")
        }

        // Create ICE servers
        var servers: [RTCIceServer] = []

        // STUN server
        let stunServer = RTCIceServer(urlStrings: ["stun:chutalk.ksc-sys.com:3478"])
        servers.append(stunServer)
        print("✅ CallManager: Added STUN server: stun:chutalk.ksc-sys.com:3478")

        // TURN servers
        for url in turnCredentials.urls {
            let turnServer = RTCIceServer(
                urlStrings: [url],
                username: turnCredentials.username,
                credential: turnCredentials.credential
            )
            servers.append(turnServer)
            print("✅ CallManager: Added TURN server: \(url)")
        }

        // Setup peer connection with current call type
        print("🔵 CallManager: Setting up peer connection - isVideo: \(isVideoCall)")
        print("🔵 CallManager: Total ICE servers: \(servers.count)")
        try await webRTCService.setupPeerConnection(iceServers: servers, isVideo: isVideoCall)
    }

    @MainActor
    private func handleIncomingOffer(from userId: Int, sdp: String) async {
        print("🔵 CallManager: Received offer from user \(userId) via Socket.io")

        // Get contact info
        do {
            guard let contact = try await ContactsService.shared.getContact(byId: userId) else {
                print("❌ CallManager: Unknown contact \(userId)")
                return
            }

            // Generate call ID and UUID
            guard let myUserId = AuthService.shared.currentUser?.id else {
                print("❌ CallManager: No current user")
                return
            }

            let callId = "\(userId)-\(myUserId)"  // caller-receiver format
            let uuid = UUID()

            // Detect video from SDP using accurate detection
            let hasVideo = detectVideoFromSDP(sdp)

            print("📞 CallManager: Reporting incoming call to CallKit")
            print("   Call ID: \(callId)")
            print("   UUID: \(uuid)")
            print("   Has Video: \(hasVideo)")

            // Store call info
            self.currentContact = contact
            self.callDirection = .incoming
            self.callState = .ringing
            self.isVideoCall = hasVideo
            self.callId = callId
            self.callUUID = uuid
            self.incomingOffer = sdp
            self.incomingCallerId = userId

            // Report to CallKit (this will show native iOS call UI)
            CallKitProvider.shared.reportIncomingCall(
                uuid: uuid,
                handle: contact.displayName,
                hasVideo: hasVideo,
                callId: callId,
                callerId: userId
            ) {
                print("✅ CallManager: CallKit report completed for Socket.io offer")
            }

            print("✅ CallManager: Incoming call from \(contact.displayName) via Socket.io")
        } catch {
            print("❌ CallManager: Failed to handle incoming offer - \(error)")
        }
    }

    @MainActor
    private func handleIncomingAnswer(sdp: String) async {
        print("🔵 CallManager: Received answer")

        // Prevent processing answer if we're not the caller
        guard callDirection == .outgoing else {
            print("⚠️ CallManager: Ignoring answer - not the caller")
            return
        }

        // Check if we're in the right state to receive answer
        guard callState == .connecting else {
            print("⚠️ CallManager: Ignoring answer - wrong call state: \(callState)")
            return
        }

        // Prevent duplicate answer processing
        guard !answerReceived else {
            print("⚠️ CallManager: Ignoring duplicate answer")
            return
        }

        // Mark answer as received
        answerReceived = true
        print("✅ CallManager: Processing answer (first time)")

        do {
            // Set remote description (answer)
            try await webRTCService.setRemoteDescription(sdp: sdp, type: .answer)

            // Add pending ICE candidates
            for candidateDict in pendingIceCandidates {
                handleRemoteIceCandidate(candidate: candidateDict)
            }
            pendingIceCandidates.removeAll()

            print("✅ CallManager: Answer processed successfully")
        } catch {
            print("❌ CallManager: Failed to handle answer - \(error)")
            await endCall()
        }
    }

    private func handleRemoteIceCandidate(candidate: [String: Any]) {
        guard let sdpMid = candidate["sdpMid"] as? String,
              let sdpMLineIndex = candidate["sdpMLineIndex"] as? Int32,
              let sdp = candidate["candidate"] as? String else {
            print("❌ CallManager: Invalid ICE candidate format")
            FileLogger.shared.log("❌ Invalid ICE candidate format", category: "CallManager")
            return
        }

        print("📥 CallManager: Received ICE candidate - mid: \(sdpMid), index: \(sdpMLineIndex)")
        FileLogger.shared.log("📥 Received ICE candidate - mid: \(sdpMid), index: \(sdpMLineIndex)", category: "CallManager")

        let iceCandidate = RTCIceCandidate(
            sdp: sdp,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        // If peer connection is ready, add candidate immediately
        // Otherwise, queue it for later
        if webRTCService.isReadyForCandidates {
            webRTCService.addIceCandidate(iceCandidate)
            print("✅ CallManager: Added ICE candidate immediately")
            FileLogger.shared.log("✅ Added ICE candidate immediately", category: "CallManager")
        } else {
            pendingIceCandidates.append(candidate)
            print("⏳ CallManager: Queued ICE candidate (peer connection not ready)")
            FileLogger.shared.log("⏳ Queued ICE candidate (peer connection not ready)", category: "CallManager")
        }
    }

    private func startCallTimer() {
        callStartTime = Date()
        callTimer?.invalidate()

        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.callStartTime else { return }

            Task { @MainActor in
                self.callDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callStartTime = nil
    }

    // MARK: - Ringback Tone (呼び出し音)

    private func startRingbackTone() {
        print("🔔 CallManager: Starting ringback tone (呼び出し音)")

        // 既存のタイマーを停止
        stopRingbackTone()

        // 1秒ごとに「ツー」という音を再生
        ringbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // システム音 1016 = よりクリアな呼び出し音
            // 他の選択肢: 1013(低音), 1014(中音), 1015(高音), 1016(クリア), 1050-1070(各種通知音)
            AudioServicesPlaySystemSound(SystemSoundID(1014))
        }

        // 初回は即座に再生
        AudioServicesPlaySystemSound(SystemSoundID(1016))
    }

    private func stopRingbackTone() {
        ringbackTimer?.invalidate()
        ringbackTimer = nil
        print("🔕 CallManager: Stopped ringback tone")
    }

    // MARK: - Helper Methods

    /// SDPを解析してビデオトラックが有効かどうかを判別
    private func detectVideoFromSDP(_ sdp: String) -> Bool {
        let lines = sdp.components(separatedBy: .newlines)
        var inVideoSection = false
        var videoPort: Int?

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // m=video行を検出
            if trimmedLine.hasPrefix("m=video") {
                inVideoSection = true
                // m=video 9 RTP/SAVPF 96 の形式からportを抽出
                let components = trimmedLine.components(separatedBy: " ")
                if components.count >= 2, let port = Int(components[1]) {
                    videoPort = port
                }
            } else if trimmedLine.hasPrefix("m=") {
                // 別のメディアセクションに入ったのでビデオセクション終了
                inVideoSection = false
            }

            // ビデオセクション内でa=inactive属性をチェック
            if inVideoSection && trimmedLine == "a=inactive" {
                print("🔍 CallManager: Video track is inactive in SDP")
                return false
            }
        }

        // videoPortが0でない場合、ビデオが有効
        if let port = videoPort, port > 0 {
            print("🔍 CallManager: Video track detected in SDP (port: \(port))")
            return true
        } else {
            print("🔍 CallManager: No active video track in SDP")
            return false
        }
    }
}
