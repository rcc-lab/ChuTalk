//
//  VoIPPayload.swift
//  ChuTalk
//
//  VoIP Push通知のペイロードパーサー（型寛容版）
//

import Foundation

struct VoIPPayload {
    let type: String
    let callId: String
    let fromUserId: Int         // Int型に変更
    let fromDisplayName: String
    let room: String
    let hasVideo: Bool          // 追加
    let offer: String?          // Offer SDP (optional)

    // 寛容なペイロードパース（Int/String混在に対応）
    static func parse(from dict: [AnyHashable: Any]) -> VoIPPayload? {
        print("📦 VoIPPayload: Parsing payload...")
        print("📦 VoIPPayload: Raw payload: \(dict)")

        // 型寛容ヘルパー関数
        func str(_ key: String) -> String? {
            if let s = dict[key] as? String { return s }
            if let n = dict[key] as? NSNumber { return n.stringValue }
            if let i = dict[key] as? Int { return String(i) }
            if let v = dict[key] { return String(describing: v) }
            return nil
        }

        func int(_ key: String) -> Int? {
            if let i = dict[key] as? Int { return i }
            if let n = dict[key] as? NSNumber { return n.intValue }
            if let s = dict[key] as? String, let i = Int(s) { return i }
            return nil
        }

        func bool(_ key: String) -> Bool? {
            if let b = dict[key] as? Bool { return b }
            if let n = dict[key] as? NSNumber { return n.boolValue }
            if let s = dict[key] as? String { return s.lowercased() == "true" }
            return nil
        }

        // type（デフォルト値あり）
        let type = str("type") ?? "call.incoming"

        // callId（必須 - なければUUID生成）
        guard let callId = str("callId") else {
            print("❌ VoIPPayload: Missing callId, using UUID")
            return nil  // callIdは最低限必要
        }

        // callerId（Int、デフォルト0）- サーバーから callerId で送信される
        let fromUserId = int("callerId") ?? int("fromUserId") ?? 0

        // callerName（デフォルト値あり）- サーバーから callerName で送信される
        let fromDisplayName = str("callerName") ?? str("fromDisplayName") ?? "Unknown"

        // room（デフォルト値あり）
        let room = str("room") ?? ""

        // hasVideo（デフォルトtrue）
        let hasVideo = bool("hasVideo") ?? true

        // offer SDP（optional）
        let offer = str("offer")

        print("✅ VoIPPayload: Successfully parsed")
        print("   type: \(type)")
        print("   callId: \(callId)")
        print("   fromUserId: \(fromUserId) (Int)")
        print("   fromDisplayName: \(fromDisplayName)")
        print("   room: \(room)")
        print("   hasVideo: \(hasVideo)")
        print("   offer: \(offer != nil ? "present (\(offer!.count) chars)" : "nil")")

        return VoIPPayload(
            type: type,
            callId: callId,
            fromUserId: fromUserId,
            fromDisplayName: fromDisplayName,
            room: room,
            hasVideo: hasVideo,
            offer: offer
        )
    }
}
