//
//  CallKitService.swift
//  ChuTalk
//
//  CallKit統合（着信UI、応答/拒否処理）
//

import Foundation
import Combine
import CallKit
import AVFoundation
import UIKit

class CallKitService: NSObject, ObservableObject {
    static let shared = CallKitService()

    private let provider: CXProvider
    private let callController = CXCallController()

    private var currentCallUUID: UUID?
    private var currentCallerId: Int?

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "ChuTalk")
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.iconTemplateImageData = UIImage(systemName: "phone.fill")?.pngData()

        // 着信音を有効化
        configuration.ringtoneSound = "Ringtone.caf"
        configuration.includesCallsInRecents = true

        self.provider = CXProvider(configuration: configuration)
        super.init()

        provider.setDelegate(self, queue: nil)

        print("✅ CallKitService: Initialized")
    }

    // MARK: - Incoming Call

    func reportIncomingCall(
        uuid: UUID,
        handle: String,
        hasVideo: Bool,
        callerId: Int,
        completion: @escaping () -> Void
    ) {
        print("📞 CallKitService: ========== INCOMING CALL ==========")
        print("📞 CallKitService: UUID: \(uuid)")
        print("📞 CallKitService: Handle: \(handle)")
        print("📞 CallKitService: Has Video: \(hasVideo)")
        print("📞 CallKitService: Caller ID: \(callerId)")

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        update.localizedCallerName = handle

        currentCallUUID = uuid
        currentCallerId = callerId

        print("📞 CallKitService: Calling provider.reportNewIncomingCall...")

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("❌ CallKitService: Failed to report incoming call")
                print("❌ CallKitService: Error: \(error)")
                print("❌ CallKitService: Error code: \((error as NSError).code)")
                print("❌ CallKitService: Error domain: \((error as NSError).domain)")
            } else {
                print("✅ CallKitService: Incoming call reported successfully")
                print("✅ CallKitService: CallKit UI should be visible now")
            }
            completion()
        }
    }

    // MARK: - Outgoing Call

    func startOutgoingCall(to contactName: String, contactId: Int, hasVideo: Bool) {
        let uuid = UUID()
        let handle = CXHandle(type: .generic, value: contactName)

        currentCallUUID = uuid
        currentCallerId = contactId

        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = hasVideo

        let transaction = CXTransaction(action: startCallAction)

        callController.request(transaction) { error in
            if let error = error {
                print("❌ CallKitService: Failed to start outgoing call - \(error)")
            } else {
                print("✅ CallKitService: Outgoing call started - UUID: \(uuid)")

                // CallManagerに通知
                Task { @MainActor in
                    // 既存のCallManagerのstartCall処理を呼ぶ
                }
            }
        }
    }

    // MARK: - End Call

    func endCall() {
        guard let uuid = currentCallUUID else {
            print("⚠️ CallKitService: No active call to end")
            return
        }

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callController.request(transaction) { error in
            if let error = error {
                print("❌ CallKitService: Failed to end call - \(error)")
            } else {
                print("✅ CallKitService: Call ended - UUID: \(uuid)")
            }
        }

        currentCallUUID = nil
        currentCallerId = nil
    }
}

// MARK: - CXProviderDelegate

extension CallKitService: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        print("🔄 CallKitService: Provider reset")
        currentCallUUID = nil
        currentCallerId = nil
    }

    // 応答
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("📞 CallKitService: User answered call - UUID: \(action.callUUID)")

        // オーディオセッション設定
        configureAudioSession()

        // CallManagerに通知
        if let callerId = currentCallerId {
            Task { @MainActor in
                // NotificationCenterで通知
                NotificationCenter.default.post(
                    name: .callKitAnswerCall,
                    object: nil,
                    userInfo: ["callerId": callerId, "callUUID": action.callUUID.uuidString]
                )
            }
        }

        action.fulfill()
    }

    // 拒否/終了
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("📞 CallKitService: Call ended by user - UUID: \(action.callUUID)")

        // CallManagerに通知
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .callKitEndCall,
                object: nil,
                userInfo: ["callUUID": action.callUUID.uuidString]
            )
        }

        currentCallUUID = nil
        currentCallerId = nil

        action.fulfill()
    }

    // 発信開始
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("📞 CallKitService: Starting outgoing call - UUID: \(action.callUUID)")

        configureAudioSession()

        action.fulfill()
    }

    // ミュート
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("🔇 CallKitService: Mute toggled - \(action.isMuted)")

        // CallManagerに通知
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .callKitSetMuted,
                object: nil,
                userInfo: ["isMuted": action.isMuted]
            )
        }

        action.fulfill()
    }

    // 保留
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        print("⏸️ CallKitService: Hold toggled - \(action.isOnHold)")
        action.fulfill()
    }

    // オーディオセッション有効化
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("🔊 CallKitService: Audio session activated")

        // WebRTCのオーディオを開始
        Task { @MainActor in
            NotificationCenter.default.post(name: .callKitAudioSessionActivated, object: nil)
        }
    }

    // オーディオセッション無効化
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("🔇 CallKitService: Audio session deactivated")
    }

    // オーディオセッション設定
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [])
            try audioSession.setActive(true)
            print("✅ CallKitService: Audio session configured")
        } catch {
            print("❌ CallKitService: Audio session error - \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let callKitAnswerCall = Notification.Name("callKitAnswerCall")
    static let callKitEndCall = Notification.Name("callKitEndCall")
    static let callKitSetMuted = Notification.Name("callKitSetMuted")
    static let callKitAudioSessionActivated = Notification.Name("callKitAudioSessionActivated")
}
