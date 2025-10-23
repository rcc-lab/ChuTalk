//
//  NotificationService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import AVFoundation

class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var hasNewMessage = false
    @Published var newMessageFrom: String?
    @Published var messageBody: String?

    @Published var hasIncomingCall = false
    @Published var incomingCallerId: Int?
    @Published var incomingCallerName: String?
    @Published var incomingOffer: String?

    private var messageTimer: Timer?
    private var callTimer: Timer?
    private var lastMessageId: Int = 0
    private var audioPlayer: AVAudioPlayer?
    private var processedCallIds = Set<String>() // 処理済みcallIdを記録

    private let processedCallIdsKey = "processedCallIds"
    private let lastMessageIdKey = "lastNotifiedMessageId"  // 最後に通知したメッセージID

    private init() {
        // UserDefaultsから処理済みcallIdsと最終メッセージIDを読み込む
        loadProcessedCallIds()
        loadLastMessageId()
    }

    private func loadProcessedCallIds() {
        if let savedIds = UserDefaults.standard.array(forKey: processedCallIdsKey) as? [String] {
            processedCallIds = Set(savedIds)
            print("📦 NotificationService: Loaded processedCallIds from UserDefaults: \(processedCallIds)")
        }
    }

    private func saveProcessedCallIds() {
        UserDefaults.standard.set(Array(processedCallIds), forKey: processedCallIdsKey)
    }

    private func loadLastMessageId() {
        lastMessageId = UserDefaults.standard.integer(forKey: lastMessageIdKey)
        print("📦 NotificationService: Loaded lastMessageId from UserDefaults: \(lastMessageId)")
    }

    private func saveLastMessageId() {
        UserDefaults.standard.set(lastMessageId, forKey: lastMessageIdKey)
        print("💾 NotificationService: Saved lastMessageId to UserDefaults: \(lastMessageId)")
    }

    func startMonitoring(userId: Int) {
        print("✅ NotificationService: Starting monitoring for user \(userId)")
        print("✅ NotificationService: メッセージと着信のポーリングを開始します")
        stopMonitoring()

        // メッセージを2秒ごとにチェック
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkNewMessages(userId: userId)
            }
        }

        // 着信を1秒ごとにチェック
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkIncomingCalls(userId: userId)
            }
        }

        // 初回チェックは即座に実行
        Task { [weak self] in
            guard let self = self else { return }
            await self.checkIncomingCalls(userId: userId)
        }

        print("✅ NotificationService: タイマー設定完了 - メッセージ: 2秒, 着信: 1秒")
    }

    private func cleanupOldSignals(userId: Int) async {
        print("🧹 NotificationService: Cleaning up old signals for user \(userId)")

        // 全ての可能なcallIdを並列で削除
        await withTaskGroup(of: Bool.self) { group in
            for callerId in 1...50 {
                // 着信側（callerId → userId）
                group.addTask {
                    let incomingCallId = "\(callerId)-\(userId)"
                    do {
                        try await self.deleteSignaling(callId: incomingCallId)
                        return true
                    } catch {
                        return false
                    }
                }

                // 発信側（userId → callerId）
                group.addTask {
                    let outgoingCallId = "\(userId)-\(callerId)"
                    do {
                        try await self.deleteSignaling(callId: outgoingCallId)
                        return true
                    } catch {
                        return false
                    }
                }
            }

            var deletedCount = 0
            for await success in group {
                if success {
                    deletedCount += 1
                }
            }

            print("🧹 NotificationService: Cleanup complete - deleted \(deletedCount) old signals")
        }

        // processedCallIdsもクリア（古いデータは無効）
        processedCallIds.removeAll()
        saveProcessedCallIds()
        print("🧹 NotificationService: Cleared processedCallIds")
    }

    func stopMonitoring() {
        print("⏹️ NotificationService: Stopping monitoring")
        messageTimer?.invalidate()
        messageTimer = nil
        callTimer?.invalidate()
        callTimer = nil
    }

    /// ログアウト時に呼び出して通知状態をリセット
    func resetNotificationState() {
        print("🔄 NotificationService: Resetting notification state")
        lastMessageId = 0
        saveLastMessageId()
        hasNewMessage = false
        newMessageFrom = nil
        messageBody = nil
    }

    private func checkNewMessages(userId: Int) async {
        // 全連絡先からの新着メッセージをチェック
        do {
            let contacts = try await ContactsService.shared.getAllContacts()

            for contact in contacts {
                let messages = try await APIService.shared.getMessages(userId: contact.id)

                // 最新メッセージが自分宛かチェック
                if let lastMessage = messages.last,
                   lastMessage.senderId == contact.id,
                   lastMessage.receiverId == userId,
                   let serverId = lastMessage.serverId,
                   serverId > lastMessageId {

                    await MainActor.run {
                        self.hasNewMessage = true
                        self.newMessageFrom = contact.displayName
                        self.messageBody = lastMessage.content
                        self.lastMessageId = serverId

                        // UserDefaultsに保存（アプリ再起動後も重複通知しない）
                        self.saveLastMessageId()

                        // メッセージ音を再生
                        AudioServicesPlaySystemSound(1007)

                        print("📨 NotificationService: 新着メッセージ from \(contact.displayName): \(lastMessage.content)")
                    }

                    // 10秒後に通知を消す
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        self.hasNewMessage = false
                    }

                    break
                }
            }
        } catch {
            // エラーは無視（ポーリングなので）
        }
    }

    private func checkIncomingCalls(userId: Int) async {
        guard !hasIncomingCall else {
            // 既に着信中の場合はスキップ
            return
        }

        // Socket.io接続中はポーリングをスキップ（Socket.ioから着信が来るため）
        if SocketService.shared.isConnected {
            print("⏩ NotificationService: Socket.io接続中のため着信ポーリングをスキップ")
            return
        }

        // デバッグ用（毎回ログ出力）
        print("🔍 NotificationService: 着信チェック開始 - User ID: \(userId) (Socket.io未接続)")

        var checkedCount = 0
        var foundSignals = 0

        // 全ユーザーからの着信をチェック（1-50の範囲）
        for callerId in 1...50 {
            if callerId == userId { continue }

            // 正しい形式: "発信者ID-着信者ID"
            let callId = "\(callerId)-\(userId)"

            // APIから直接取得
            guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else {
                print("❌ NotificationService: Invalid URL for callId: \(callId)")
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else {
                print("❌ NotificationService: No auth token")
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }

                // デバッグ: 全てのレスポンスをログ出力
                if callerId <= 12 {  // 最初の数個だけログ出力
                    print("🔍 NotificationService: Checked callId \(callId) - Status: \(httpResponse.statusCode)")
                    if let dataString = String(data: data, encoding: .utf8) {
                        print("🔍 NotificationService: Response: \(dataString)")
                    }
                }

                if httpResponse.statusCode == 200 {
                    checkedCount += 1

                    // レスポンスを解析（2つの形式をサポート）
                    guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
                        continue
                    }

                    var offerSDP: String?

                    // 形式1: オブジェクト形式 {"offer": {"sdp": "..."}, "candidates": [...]}
                    if let jsonDict = jsonObject as? [String: Any] {
                        // answerが存在する場合は通話完了済みなので無視
                        if let answer = jsonDict["answer"] as? [String: Any],
                           let answerSDP = answer["sdp"] as? String,
                           !answerSDP.isEmpty {
                            print("🔍 NotificationService: CallID \(callId) already has answer - skipping (completed call)")
                            // このcallIdが処理済みリストにあれば削除してクリーンアップ
                            if processedCallIds.contains(callId) {
                                processedCallIds.remove(callId)
                                saveProcessedCallIds()
                            }
                            continue
                        }

                        if let offer = jsonDict["offer"] as? [String: Any],
                           let sdp = offer["sdp"] as? String,
                           !sdp.isEmpty {
                            foundSignals += 1
                            print("🔍 NotificationService: Signals found for callId \(callId) (object format)")
                            offerSDP = sdp
                        }
                    }
                    // 形式2: 配列形式 [{"action": "offer", "data": {"sdp": "..."}}]
                    else if let jsonArray = jsonObject as? [[String: Any]] {
                        if !jsonArray.isEmpty {
                            foundSignals += 1
                            print("🔍 NotificationService: Signals found for callId \(callId): \(jsonArray.count) signals")
                        }

                        // answerが存在するかチェック
                        let hasAnswer = jsonArray.contains { signal in
                            if let action = signal["action"] as? String, action == "answer",
                               let data = signal["data"] as? [String: Any],
                               let sdp = data["sdp"] as? String,
                               !sdp.isEmpty {
                                return true
                            }
                            return false
                        }

                        if hasAnswer {
                            print("🔍 NotificationService: CallID \(callId) already has answer - skipping (completed call)")
                            // このcallIdが処理済みリストにあれば削除してクリーンアップ
                            if processedCallIds.contains(callId) {
                                processedCallIds.remove(callId)
                                saveProcessedCallIds()
                            }
                            continue
                        }

                        // offerシグナルを探す
                        for signal in jsonArray {
                            if let action = signal["action"] as? String,
                               action == "offer",
                               let data = signal["data"] as? [String: Any],
                               let sdp = data["sdp"] as? String,
                               !sdp.isEmpty {
                                offerSDP = sdp
                                break
                            }
                        }
                    }

                    // offerが見つかった場合、着信処理
                    if let sdp = offerSDP {
                        // 既に処理済みかチェック
                        if processedCallIds.contains(callId) {
                            print("⏩ NotificationService: CallID \(callId) は既に処理済み")
                            continue
                        }

                        print("📞 NotificationService: 着信検出！ CallID: \(callId)")
                        print("📞 NotificationService: 発信者: \(callerId) → 着信者: \(userId)")
                        print("📞 NotificationService: SDP length: \(sdp.count)")

                        // 処理済みとしてマーク
                        processedCallIds.insert(callId)
                        saveProcessedCallIds()
                        print("✅ NotificationService: Added to processedCallIds: \(callId)")
                        print("✅ NotificationService: Current processedCallIds: \(processedCallIds)")

                        // 発信者の名前を取得
                        let callerName = await getCallerName(callerId: callerId)
                        print("📞 NotificationService: Caller name: \(callerName)")

                        // SDPから通話タイプを判別（ビデオ/音声）
                        let hasVideo = sdp.contains("m=video")
                        print("📞 NotificationService: Call type: \(hasVideo ? "ビデオ通話" : "音声通話")")

                        // CallKitで着信を表示
                        let callUUID = UUID()
                        print("📞 NotificationService: Calling CallKitProvider.reportIncomingCall")

                        // completionは非同期で呼ばれるため、結果を待たずにreturn
                        // エラーがあった場合はCallKitProviderが自動的にactiveCallsInfoから削除する
                        CallKitProvider.shared.reportIncomingCall(
                            uuid: callUUID,
                            handle: callerName,
                            hasVideo: hasVideo,
                            callId: callId,
                            callerId: callerId,
                            completion: {
                                print("✅ NotificationService: CallKit completion handler called")
                            }
                        )

                        // 着信情報を保存（CallKit応答時に使用）
                        await MainActor.run {
                            self.hasIncomingCall = true
                            self.incomingCallerId = callerId
                            self.incomingCallerName = callerName
                            self.incomingOffer = sdp

                            // CallManagerにもcallIdを設定（拒否時のクリーンアップのため）
                            CallManager.shared.callId = callId
                        }

                        // 次のポーリングで同じ着信を検出しないようにreturn
                        return
                    } else {
                        // offerが見つからない場合、processedCallIdsに含まれていれば削除
                        // （発信者がキャンセルした、または通話終了でsignalが削除された）
                        if processedCallIds.contains(callId) {
                            print("🧹 NotificationService: CallID \(callId) のsignalが見つからないため、processedCallIdsから削除")
                            processedCallIds.remove(callId)
                            saveProcessedCallIds()
                            print("🧹 NotificationService: Remaining processedCallIds: \(processedCallIds)")
                        }
                    }
                }
            } catch {
                print("❌ NotificationService: Error checking callId \(callId): \(error)")
                continue
            }
        }

        print("🔍 NotificationService: 着信チェック完了 - checked: \(checkedCount), found signals: \(foundSignals)")
    }

    private func getCallerName(callerId: Int) async -> String {
        do {
            let contacts = try await ContactsService.shared.getAllContacts()
            if let contact = contacts.first(where: { $0.id == callerId }) {
                return contact.displayName
            }
        } catch {
            print("⚠️ NotificationService: Failed to get caller name")
        }
        return "User \(callerId)"
    }

    func playRingtone() {
        print("🔔 NotificationService: Playing ringtone")

        // オーディオセッションを設定
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("❌ NotificationService: Failed to setup audio session - \(error)")
        }

        // システムサウンドを繰り返し再生（シンプルで確実な方法）
        playSystemRingtone()
    }

    private func playSystemRingtone() {
        print("🔔 NotificationService: Starting system ringtone loop")

        // システムサウンドを0.5秒ごとに再生
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, self.hasIncomingCall, count < 30 else {
                print("⏹️ NotificationService: Stopping ringtone timer (count: \(count))")
                timer.invalidate()
                return
            }

            // 着信音（システムサウンド1005）
            AudioServicesPlaySystemSound(SystemSoundID(1005))

            // バイブレーション（2回に1回）
            if count % 2 == 0 {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }

            count += 1

            if count == 1 {
                print("✅ NotificationService: Ringtone playing")
            }
        }
    }

    func stopRingtone() {
        print("🔕 NotificationService: Stopping ringtone")
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func acceptCall() {
        print("✅ NotificationService: Accepting call from \(incomingCallerId ?? -1)")
        stopRingtone()

        // CallManagerに通知を送る
        if let callerId = incomingCallerId, let offer = incomingOffer {
            NotificationCenter.default.post(
                name: .acceptIncomingCall,
                object: nil,
                userInfo: [
                    "callerId": callerId,
                    "offer": offer,
                    "callerName": incomingCallerName ?? "不明"
                ]
            )
        }

        hasIncomingCall = false
        incomingCallerId = nil
        incomingOffer = nil
    }

    func declineCall() {
        print("❌ NotificationService: Declining call from \(incomingCallerId ?? -1)")
        stopRingtone()

        if let callerId = incomingCallerId,
           let userId = AuthService.shared.currentUser?.id {
            // 正しい形式: "発信者ID-着信者ID"
            let callId = "\(callerId)-\(userId)"

            print("❌ NotificationService: Deleting signals for callId: \(callId)")

            // シグナリング情報を削除
            Task {
                try? await deleteSignaling(callId: callId)
            }

            // processedCallIdsからも削除
            clearProcessedCallId(callId)
        }

        hasIncomingCall = false
        incomingCallerId = nil
        incomingOffer = nil
    }

    private func deleteSignaling(callId: String) async throws {
        guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, _) = try await URLSession.shared.data(for: request)
    }

    // 処理済みcallIdをクリア（通話終了時に呼ぶ）
    func clearProcessedCallId(_ callId: String) {
        processedCallIds.remove(callId)
        saveProcessedCallIds()
        print("🗑️ NotificationService: Cleared processed callId: \(callId)")
        print("🗑️ NotificationService: Remaining processedCallIds: \(processedCallIds)")
    }
}

extension Notification.Name {
    static let acceptIncomingCall = Notification.Name("acceptIncomingCall")
}
