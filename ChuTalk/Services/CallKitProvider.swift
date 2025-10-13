//
//  CallKitProvider.swift
//  ChuTalk
//
//  CallKit統合（VoIP着信UI、応答/拒否処理）
//

import Foundation
import CallKit
import AVFoundation
import UIKit

class CallKitProvider: NSObject {
    static let shared = CallKitProvider()

    private let provider: CXProvider
    private let callController = CXCallController()

    // 現在の通話情報
    private var activeCallsInfo: [UUID: CallInfo] = [:]

    // CallID → UUID のマッピング（重複着信防止用）
    private var callIdToUUID: [String: UUID] = [:]

    struct CallInfo {
        let callId: String
        let callerId: Int
        let callerName: String
        let hasVideo: Bool
    }

    private override init() {
        // CXProviderConfiguration
        let configuration = CXProviderConfiguration(localizedName: "ChuTalk")
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.includesCallsInRecents = true

        // アイコン設定
        if let icon = UIImage(systemName: "phone.fill") {
            configuration.iconTemplateImageData = icon.pngData()
        }

        // 着信音は システム標準を使用
        // configuration.ringtoneSound = nil  // システムデフォルト

        self.provider = CXProvider(configuration: configuration)
        super.init()

        provider.setDelegate(self, queue: nil)

        print("✅ CallKitProvider: Initialized")
    }

    // MARK: - Incoming Call

    func reportIncomingCall(
        uuid: UUID,
        handle: String,
        hasVideo: Bool,
        callId: String,
        callerId: Int,
        completion: @escaping () -> Void
    ) {
        print("📞 CallKitProvider: ========== REPORTING INCOMING CALL ==========")
        print("   UUID: \(uuid)")
        print("   Handle: \(handle)")
        print("   Has Video: \(hasVideo)")
        print("   Call ID: \(callId)")
        print("   Caller ID: \(callerId)")

        // 重複チェック: 同じcallIdが既に報告されている場合はスキップ（デバッグ用に一時無効化）
        if let existingUUID = callIdToUUID[callId] {
            print("⚠️ CallKitProvider: Call ID \(callId) already reported with UUID \(existingUUID)")
            print("⚠️ CallKitProvider: 【デバッグ】重複チェックを無視して続行")
            // 一時的にコメントアウト
            // completion()
            // return
        }

        // callIdとUUIDのマッピングを保存
        callIdToUUID[callId] = uuid

        // 通話情報を保存
        let callInfo = CallInfo(
            callId: callId,
            callerId: callerId,
            callerName: handle,
            hasVideo: hasVideo
        )
        activeCallsInfo[uuid] = callInfo

        // CXCallUpdate作成
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: handle)
        update.hasVideo = hasVideo
        update.localizedCallerName = handle
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        print("📞 CallKitProvider: Calling provider.reportNewIncomingCall...")

        // CallKitに着信を報告
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if let error = error {
                print("❌ CallKitProvider: Failed to report incoming call")
                print("   Error: \(error)")
                print("   Error code: \((error as NSError).code)")
                print("   Error domain: \((error as NSError).domain)")
                self?.activeCallsInfo.removeValue(forKey: uuid)
                self?.callIdToUUID.removeValue(forKey: callId)
            } else {
                print("✅ CallKitProvider: Incoming call reported successfully")
                print("✅ CallKitProvider: CallKit UI should be visible now")
            }
            completion()
        }
    }

    // MARK: - Outgoing Call

    func startOutgoingCall(
        uuid: UUID,
        to contactName: String,
        contactId: Int,
        hasVideo: Bool,
        callId: String
    ) {
        print("📞 CallKitProvider: Starting outgoing call")
        print("   UUID: \(uuid)")
        print("   Contact: \(contactName)")
        print("   Call ID: \(callId)")
        print("   Has Video: \(hasVideo)")

        // 通話情報を保存
        let callInfo = CallInfo(
            callId: callId,
            callerId: contactId,
            callerName: contactName,
            hasVideo: hasVideo
        )
        activeCallsInfo[uuid] = callInfo

        let handle = CXHandle(type: .generic, value: contactName)
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        startCallAction.isVideo = hasVideo

        let transaction = CXTransaction(action: startCallAction)

        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("❌ CallKitProvider: Failed to start outgoing call - \(error)")
                self?.activeCallsInfo.removeValue(forKey: uuid)
            } else {
                print("✅ CallKitProvider: Outgoing call started - UUID: \(uuid)")

                // CallManagerに通知
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .callKitStartCall,
                        object: nil,
                        userInfo: [
                            "callUUID": uuid.uuidString,
                            "callId": callId,
                            "contactId": contactId,
                            "contactName": contactName,
                            "hasVideo": hasVideo
                        ]
                    )
                }
            }
        }
    }

    // MARK: - End Call

    func endCall(uuid: UUID) {
        print("📞 CallKitProvider: Ending call - UUID: \(uuid)")

        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("❌ CallKitProvider: Failed to end call - \(error)")
            } else {
                print("✅ CallKitProvider: Call ended - UUID: \(uuid)")

                // callIdToUUIDマッピングも削除
                if let callInfo = self?.activeCallsInfo[uuid] {
                    self?.callIdToUUID.removeValue(forKey: callInfo.callId)
                    print("🗑️ CallKitProvider: Removed callId mapping: \(callInfo.callId)")
                }

                self?.activeCallsInfo.removeValue(forKey: uuid)
            }
        }
    }

    // MARK: - Call Information

    func getCallInfo(for uuid: UUID) -> CallInfo? {
        return activeCallsInfo[uuid]
    }
}

// MARK: - CXProviderDelegate

extension CallKitProvider: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        print("🔄 CallKitProvider: Provider reset")
        activeCallsInfo.removeAll()
        callIdToUUID.removeAll()

        // すべての通話を終了
        Task { @MainActor in
            NotificationCenter.default.post(name: .callKitReset, object: nil)
        }
    }

    // 応答
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("📞 CallKitProvider: ========== USER ANSWERED CALL ==========")
        print("   UUID: \(action.callUUID)")

        guard let callInfo = activeCallsInfo[action.callUUID] else {
            print("❌ CallKitProvider: No call info found for UUID: \(action.callUUID)")
            action.fail()
            return
        }

        print("   Call ID: \(callInfo.callId)")
        print("   Caller ID: \(callInfo.callerId)")
        print("   Caller Name: \(callInfo.callerName)")

        // オーディオセッション設定はdidActivate audioSessionで行う
        // ここでは設定しない（CallKitが自動的に設定する）

        // CallManagerに通知
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .callKitAnswerCall,
                object: nil,
                userInfo: [
                    "callUUID": action.callUUID.uuidString,
                    "callId": callInfo.callId,
                    "callerId": callInfo.callerId,
                    "callerName": callInfo.callerName,
                    "hasVideo": callInfo.hasVideo
                ]
            )
        }

        action.fulfill()
    }

    // 拒否/終了
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("📞 CallKitProvider: ========== CALL ENDED ==========")
        print("   UUID: \(action.callUUID)")

        guard let callInfo = activeCallsInfo[action.callUUID] else {
            print("⚠️ CallKitProvider: No call info found for UUID: \(action.callUUID)")
            action.fulfill()
            return
        }

        print("   Call ID: \(callInfo.callId)")

        // CallManagerに通知
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .callKitEndCall,
                object: nil,
                userInfo: [
                    "callUUID": action.callUUID.uuidString,
                    "callId": callInfo.callId
                ]
            )
        }

        // マッピングも削除
        callIdToUUID.removeValue(forKey: callInfo.callId)
        activeCallsInfo.removeValue(forKey: action.callUUID)
        action.fulfill()
    }

    // 発信開始
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("📞 CallKitProvider: ========== STARTING OUTGOING CALL ==========")
        print("   UUID: \(action.callUUID)")

        // オーディオセッション設定はdidActivate audioSessionで行う
        // ここでは設定しない（CallKitが自動的に設定する）

        // 接続中と報告
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        action.fulfill()
    }

    // ミュート
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        print("🔇 CallKitProvider: Mute toggled - \(action.isMuted)")

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
        print("⏸️ CallKitProvider: Hold toggled - \(action.isOnHold)")
        action.fulfill()
    }

    // オーディオセッション有効化
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("🔊 CallKitProvider: Audio session activated by CallKit")

        // CallKitがaudio sessionを有効化した後、WebRTC用に設定
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            print("✅ CallKitProvider: Audio session configured for WebRTC")
        } catch {
            print("❌ CallKitProvider: Failed to configure audio session - \(error)")
        }

        // WebRTCのオーディオを開始
        Task { @MainActor in
            NotificationCenter.default.post(name: .callKitAudioSessionActivated, object: nil)
        }
    }

    // オーディオセッション無効化
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("🔇 CallKitProvider: Audio session deactivated")
    }

    // オーディオセッション設定
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            try audioSession.setActive(true)
            print("✅ CallKitProvider: Audio session configured")
        } catch {
            print("❌ CallKitProvider: Audio session error - \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // callKitAnswerCall, callKitEndCall, callKitSetMuted, callKitAudioSessionActivatedは
    // CallKitService.swiftで既に定義されているため、ここでは新規のもののみ定義
    static let callKitStartCall = Notification.Name("callKitStartCall")
    static let callKitReset = Notification.Name("callKitReset")
}
