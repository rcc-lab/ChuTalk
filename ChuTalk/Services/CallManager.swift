//
//  CallManager.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import WebRTC
import Combine

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

        guard let userInfo = notification.userInfo,
              let callUUID = userInfo["callUUID"] as? String,
              let callId = userInfo["callId"] as? String,
              let callerId = userInfo["callerId"] as? Int,
              let callerName = userInfo["callerName"] as? String,
              let hasVideo = userInfo["hasVideo"] as? Bool else {
            print("❌ CallManager: Invalid notification userInfo")
            return
        }

        print("📞 CallManager: User accepted call via CallKit")
        print("   Call UUID: \(callUUID)")
        print("   Call ID: \(callId)")
        print("   Caller ID: \(callerId)")
        print("   Caller Name: \(callerName)")
        print("   Has Video: \(hasVideo)")

        Task { @MainActor in
            // CallManagerの状態を設定（VoIP Push経由の場合に必要）
            print("🔧 CallManager: Setting up state from CallKit notification...")

            self.callId = callId
            self.callUUID = UUID(uuidString: callUUID)
            self.isVideoCall = hasVideo
            self.callDirection = .incoming

            // ContactsServiceから連絡先を取得
            do {
                print("🔧 CallManager: Fetching contact for callerId: \(callerId)...")
                if let contact = try await ContactsService.shared.getContact(byId: callerId) {
                    self.currentContact = contact
                    print("✅ CallManager: Contact set: \(contact.displayName)")
                } else {
                    print("⚠️ CallManager: Contact not found, creating temporary contact")
                    // 連絡先が見つからない場合は一時的な連絡先を作成
                    self.currentContact = Contact(
                        id: callerId,
                        username: "user\(callerId)",
                        displayName: callerName,
                        isOnline: false,
                        isFavorite: false
                    )
                }

                // APIからofferを取得
                print("🔧 CallManager: Fetching offer from API for callId: \(callId)...")
                if let offerSDP = try await APIService.shared.getOfferSDP(callId: callId) {
                    self.incomingOffer = offerSDP
                    print("✅ CallManager: Offer retrieved from API, length: \(offerSDP.count)")

                    // acceptIncomingCall()を呼び出し
                    await self.acceptIncomingCall()
                } else {
                    print("❌ CallManager: No offer found in API for callId: \(callId)")
                }
            } catch {
                print("❌ CallManager: Error setting up state: \(error)")
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
                  let contact = self.currentContact else { return }

            let candidateDict: [String: Any] = [
                "sdpMid": candidate.sdpMid ?? "",
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "candidate": candidate.sdp
            ]

            // Send ICE candidate via Socket.io
            self.socketService.sendIceCandidate(to: contact.id, candidate: candidateDict)
            print("✅ CallManager: Sent ICE candidate via Socket.io to user \(contact.id)")
        }

        webRTCService.onConnected = { [weak self] in
            print("🔔 CallManager: onConnected callback triggered!")
            Task { @MainActor in
                print("🔔 CallManager: onConnected - inside MainActor block")
                print("🔔 CallManager: Current call state: \(String(describing: self?.callState))")
                self?.callState = .connected
                self?.startCallTimer()
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

        guard let currentUserId = AuthService.shared.currentUser?.id else {
            print("❌ CallManager: No current user")
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

        // CallKitで発信を開始
        CallKitProvider.shared.startOutgoingCall(
            uuid: callUUID!,
            to: contact.displayName,
            contactId: contact.id,
            hasVideo: isVideo,
            callId: callId!
        )

        // Configure audio (CallKitを使用時はCallKitが管理)
        // audioManager.configureForCall()

        // Setup WebRTC
        do {
            try await setupPeerConnection()

            // Create offer
            let offer = try await webRTCService.createOffer(isVideo: isVideo)

            // Send offer via Socket.io
            socketService.sendOffer(to: contact.id, sdp: offer.sdp)

            // Also save offer to API (for fallback)
            Task {
                do {
                    try await APIService.shared.sendSignal(
                        callId: callId!,
                        action: "offer",
                        data: ["sdp": offer.sdp, "type": "offer"]
                    )
                    print("✅ CallManager: Offer also saved to API for callId: \(callId!)")
                } catch {
                    print("⚠️ CallManager: Failed to save offer to API - \(error)")
                }
            }

            // Show call view
            self.showActiveCallView = true

            // Note: isSettingUpCallはonConnectedコールバックでfalseに設定される

            print("✅ CallManager: Offer sent via Socket.io to \(contact.displayName)")

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
        print("🔵 CallManager: incomingOffer exists: \(incomingOffer != nil)")
        print("🔵 CallManager: currentContact exists: \(currentContact != nil)")

        guard let offer = incomingOffer,
              let contact = currentContact else {
            print("❌ CallManager: Cannot accept call - missing offer or contact")
            print("❌ CallManager: incomingOffer: \(String(describing: incomingOffer?.prefix(100)))")
            print("❌ CallManager: currentContact: \(String(describing: currentContact))")
            return
        }

        print("🔵 CallManager: Accepting incoming call from \(contact.displayName)")
        print("🔵 CallManager: Offer SDP length: \(offer.count)")

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

        // Configure audio (CallKitを使用時はCallKitが管理)
        // audioManager.configureForCall()

        do {
            print("🔧 CallManager: Step 1 - Setting up peer connection...")
            // Setup peer connection
            try await setupPeerConnection()
            print("✅ CallManager: Step 1 - Peer connection setup complete")

            print("🔧 CallManager: Step 2 - Setting remote description (offer)...")
            // Set remote description (offer)
            try await webRTCService.setRemoteDescription(sdp: offer, type: .offer)
            print("✅ CallManager: Step 2 - Remote description set")

            print("🔧 CallManager: Step 3 - Creating answer...")
            // Create answer
            let answer = try await webRTCService.createAnswer(isVideo: isVideoCall)
            print("✅ CallManager: Step 3 - Answer created, SDP length: \(answer.sdp.count)")

            print("🔧 CallManager: Step 4 - Sending answer via Socket.io...")
            // Send answer via Socket.io (if connected)
            socketService.sendAnswer(to: contact.id, sdp: answer.sdp)
            print("✅ CallManager: Answer sent via Socket.io to user \(contact.id)")

            // Also save answer to API (ensures delivery even if Socket.IO not connected yet)
            if let myUserId = AuthService.shared.currentUser?.id,
               let callId = self.callId {
                do {
                    print("🔧 CallManager: Step 5 - Saving answer to API...")
                    try await APIService.shared.saveAnswer(callId: callId, sdp: answer.sdp, from: myUserId, to: contact.id)
                    print("✅ CallManager: Answer also saved to API for callId: \(callId)")
                } catch {
                    print("⚠️ CallManager: Failed to save answer to API - \(error) (continuing anyway)")
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
        } catch {
            print("❌ CallManager: ========== FAILED to accept call ==========")
            print("❌ CallManager: Error type: \(type(of: error))")
            print("❌ CallManager: Error: \(error)")
            print("❌ CallManager: Error localizedDescription: \(error.localizedDescription)")
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
            return
        }

        let iceCandidate = RTCIceCandidate(
            sdp: sdp,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        // If peer connection is ready, add candidate immediately
        // Otherwise, queue it for later
        if webRTCService.isReadyForCandidates {
            webRTCService.addIceCandidate(iceCandidate)
            print("✅ CallManager: Added ICE candidate")
        } else {
            pendingIceCandidates.append(candidate)
            print("⏳ CallManager: Queued ICE candidate")
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
