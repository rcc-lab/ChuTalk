//
//  VoIPPushService.swift
//  ChuTalk
//
//  PushKit VoIP Push通知の統合
//

import Foundation
import PushKit
import Combine
import UIKit

class VoIPPushService: NSObject, ObservableObject {
    static let shared = VoIPPushService()

    @Published var voipDeviceToken: String?

    private var pushRegistry: PKPushRegistry?
    private var pendingCallIds = Set<String>() // 二重処理防止

    private override init() {
        super.init()
        print("✅ VoIPPushService: Initializing...")
    }

    // アプリ起動時にPushKitを登録
    func registerForVoIPPushes() {
        print("📞 VoIPPushService: Registering for VoIP pushes...")

        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]

        self.pushRegistry = registry

        print("✅ VoIPPushService: PushKit registered")
    }

    // トークンをサーバーに登録（NotificationsService経由）
    private func uploadDeviceToken(_ token: String) {
        print("📤 VoIPPushService: Uploading device token via NotificationsService...")

        // NotificationsServiceに委譲（APNsトークンと統合管理）
        NotificationsService.shared.registerVoIPToken(token)
    }

    // Data → hex文字列変換
    private func hexString(from data: Data) -> String {
        return data.map { String(format: "%02.2hhx", $0) }.joined()
    }
}

// MARK: - PKPushRegistryDelegate

extension VoIPPushService: PKPushRegistryDelegate {
    // トークン更新
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        print("📞 VoIPPushService: ========== VOIP TOKEN UPDATED ==========")

        guard type == .voIP else {
            print("⚠️ VoIPPushService: Unexpected push type: \(type)")
            return
        }

        // Data → hex文字列
        let token = hexString(from: pushCredentials.token)
        print("📞 VoIPPushService: VoIP Token: \(token)")
        print("📞 VoIPPushService: Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        print("📞 VoIPPushService: VoIP Topic should be: \(Bundle.main.bundleIdentifier ?? "unknown").voip")

        // 保存
        self.voipDeviceToken = token

        // サーバーに登録
        uploadDeviceToken(token)
    }

    // VoIP Push受信（アプリがkill/バックグラウンドでも呼ばれる）
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========")
        print("📞 VoIPPushService: PUSH TYPE: \(type)")
        print("📞 VoIPPushService: APP STATE: \(UIApplication.shared.applicationState.rawValue)")
        print("📞 VoIPPushService: Payload: \(payload.dictionaryPayload)")

        guard type == .voIP else {
            print("⚠️ VoIPPushService: Unexpected push type: \(type)")
            completion()
            return
        }

        let dict = payload.dictionaryPayload

        // ペイロードをパース（寛容版）
        var voipPayload = VoIPPayload.parse(from: dict)

        // パース失敗時のフォールバック（CallKitを必ず呼ぶため）
        if voipPayload == nil {
            print("⚠️ VoIPPushService: Parse failed, creating fallback payload")

            // 最低限の情報でペイロードを構築
            let callId = (dict["callId"] as? String) ?? UUID().uuidString

            // callerName をチェック（フォールバックとして fromDisplayName もチェック）
            let displayName = (dict["callerName"] as? String) ?? (dict["fromDisplayName"] as? String) ?? "Unknown Caller"

            // callerId をチェック（フォールバックとして fromUserId もチェック）
            let fromUserId: Int = {
                if let n = dict["callerId"] as? NSNumber { return n.intValue }
                if let i = dict["callerId"] as? Int { return i }
                if let s = dict["callerId"] as? String, let i = Int(s) { return i }
                // フォールバック: 古いキー名もチェック
                if let n = dict["fromUserId"] as? NSNumber { return n.intValue }
                if let i = dict["fromUserId"] as? Int { return i }
                if let s = dict["fromUserId"] as? String, let i = Int(s) { return i }
                return 0
            }()

            let hasVideo: Bool = {
                if let b = dict["hasVideo"] as? Bool { return b }
                if let n = dict["hasVideo"] as? NSNumber { return n.boolValue }
                return true  // デフォルトはビデオ通話
            }()

            voipPayload = VoIPPayload(
                type: "call.incoming",
                callId: callId,
                fromUserId: fromUserId,
                fromDisplayName: displayName,
                room: (dict["room"] as? String) ?? "",
                hasVideo: hasVideo
            )

            print("✅ VoIPPushService: Fallback payload created")
            print("   callId: \(callId)")
            print("   fromUserId: \(fromUserId)")
            print("   fromDisplayName: \(displayName)")
            print("   hasVideo: \(hasVideo)")
        }

        // この時点でvoipPayloadは必ず存在
        guard let finalPayload = voipPayload else {
            print("❌ VoIPPushService: Critical error - no payload available")
            completion()
            return
        }

        // 二重処理防止
        guard !pendingCallIds.contains(finalPayload.callId) else {
            print("⚠️ VoIPPushService: Call \(finalPayload.callId) already being processed")
            completion()
            return
        }

        pendingCallIds.insert(finalPayload.callId)

        // call.cancel type は VoIP Push で送るべきではない（Apple のガイドライン違反）
        // Socket.io の call-ended イベントで処理されるべき
        if finalPayload.type == "call.cancel" {
            print("⚠️ VoIPPushService: Received call.cancel via VoIP Push (should use Socket.io instead)")
            print("   Call ID: \(finalPayload.callId)")
            print("   Completing push handler without calling CallKit")
            pendingCallIds.remove(finalPayload.callId)
            completion()
            return
        }

        // CallKitに着信を報告（必ずメインスレッドで実行）
        let uuid = UUID()
        let callerId = finalPayload.fromUserId

        print("📞 VoIPPushService: Reporting incoming call to CallKit")
        print("   UUID: \(uuid)")
        print("   Caller: \(finalPayload.fromDisplayName)")
        print("   Caller ID: \(callerId)")
        print("   Has Video: \(finalPayload.hasVideo)")

        // iOS 13+ requires immediate CallKit report in same run loop
        CallKitProvider.shared.reportIncomingCall(
            uuid: uuid,
            handle: finalPayload.fromDisplayName,
            hasVideo: finalPayload.hasVideo,
            callId: finalPayload.callId,
            callerId: callerId
        ) { [weak self] in
            print("✅ VoIPPushService: CallKit report completed")
            self?.pendingCallIds.remove(finalPayload.callId)
            completion()
        }
    }

    // トークン無効化
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("⚠️ VoIPPushService: VoIP token invalidated for type: \(type)")
        self.voipDeviceToken = nil
    }
}
