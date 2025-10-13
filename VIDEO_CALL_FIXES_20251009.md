# ビデオ通話の重大修正

**作成日時**: 2025年10月9日 21:00
**ステータス**: ✅ 修正完了 → 再ビルド必須

---

## 問題

ユーザー報告：
1. **ビデオ通話が確立しない**: お互い着信を受けても通話できない（昨日はできていた）
2. **ビデオ通話がビデオ用にならない**: ビデオトラックが正しく設定されていない

---

## 根本原因と修正

### 問題1: answerの重複処理

**根本原因**:
CallManager.swiftで追加したanswerポーリング機能が、Socket.IO経由のanswerと重複して`handleIncomingAnswer()`を呼び出す可能性があった。

**発生メカニズム**:
1. 発信側がSocket.IO経由でanswerを受信 → `handleIncomingAnswer()`を呼び出し
2. 同時に、ポーリング機能もAPI経由でanswerを取得 → 再度`handleIncomingAnswer()`を呼び出し
3. WebRTCの状態が壊れて通話が確立しない

**修正内容**:

#### CallManager.swift

**1. answerReceivedフラグを追加** (Line 45):
```swift
private var answerReceived: Bool = false  // answer重複処理を防ぐフラグ
```

**2. startCall()でフラグをリセット** (Line 136):
```swift
self.answerReceived = false  // Reset flag
```

**3. pollForAnswer()でフラグをチェック** (Line 201-207):
```swift
// Check if we already received answer
guard await MainActor.run(body: {
    self.callState == .connecting && self.callDirection == .outgoing && !self.answerReceived
}) else {
    print("✅ CallManager: Answer already received, stopping API polling")
    return
}
```

**4. handleIncomingAnswer()で重複チェック** (Line 526-534):
```swift
// Prevent duplicate answer processing
guard !answerReceived else {
    print("⚠️ CallManager: Ignoring duplicate answer")
    return
}

// Mark answer as received
answerReceived = true
print("✅ CallManager: Processing answer (first time)")
```

**5. endCall()でフラグをリセット** (Line 320):
```swift
self?.answerReceived = false
```

**効果**:
- ✅ answerの重複処理を完全に防止
- ✅ WebRTC状態の破損を防止
- ✅ 通話確立が安定する

---

### 問題2: SDPからのビデオ判別が不正確

**根本原因**:
`acceptIncomingCall()`メソッドで使用していた単純な`offer.contains("m=video")`チェックが不正確だった。

WebRTCのSDPでは、ビデオトラックが無効でも`m=video`行が存在する場合がある：
- `m=video 0` → portが0の場合、メディアは無効
- `a=inactive` → inactive属性がある場合、メディアは無効

**修正内容**:

#### CallManager.swift

**1. SDPを正確に解析する新メソッドを追加** (Line 598-638):
```swift
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
```

**2. acceptIncomingCall()で新メソッドを使用** (Line 362):
```swift
// SDPから通話タイプを判別
let hasVideo = detectVideoFromSDP(offer)
self.isVideoCall = hasVideo
print("🔵 CallManager: Call type from SDP: \(hasVideo ? "ビデオ通話" : "音声通話")")
```

**効果**:
- ✅ SDPから正確にビデオトラックの有無を判別
- ✅ portが0のビデオトラックを無効と判定
- ✅ inactive属性のビデオトラックを無効と判定
- ✅ ビデオ通話と音声通話を正確に区別

---

## テスト手順

### 事前準備

**1. アプリを再ビルド（必須）**
```
Xcode:
Product → Clean Build Folder (Shift + Cmd + K)
Product → Build (Cmd + B)
Product → Run (Cmd + R)
```

**2. 両デバイスで再インストール**

**3. ログイン確認**

---

### テスト1: ビデオ通話（アプリ起動中）⭐ 最重要

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10にビデオ通話で発信
3. ユーザー10が応答
4. **ビデオ・音声が双方向で通じることを確認**

**期待される結果**:
- ✅ 着信画面が即座に表示
- ✅ 応答後、ビデオ通話画面が表示
- ✅ **双方向でビデオが表示される**
- ✅ **双方向で音声が聞こえる**
- ✅ ログに「Video track detected in SDP」が表示される

**確認するログ**:
```
🔍 CallManager: Video track detected in SDP (port: 9)
🔵 CallManager: Call type from SDP: ビデオ通話
✅ CallManager: Processing answer (first time)
✅ CallManager: Answer processed successfully
🔵 WebRTCService: ICE connection state: connected
```

---

### テスト2: ビデオ通話（アプリ停止時）⭐ 最重要

**手順**:
1. ユーザー10のアプリを完全に停止（タスクマネージャーからスワイプ）
2. 30秒待つ
3. ユーザー11がユーザー10にビデオ通話で発信
4. ユーザー10でCallKit着信が表示されることを確認
5. 応答ボタンをタップ
6. **ビデオ・音声が双方向で通じることを確認**

**期待される結果**:
- ✅ CallKit着信画面が表示（ロック画面でも）
- ✅ 応答すると自動的にアプリが起動
- ✅ ビデオ通話画面が表示
- ✅ **双方向でビデオが表示される**
- ✅ **双方向で音声が聞こえる**

**ユーザー11（発信側）のログ**:
```
✅ CallManager: Offer sent via Socket.io to User 10
🔍 CallManager: Polling API for answer (attempt 1/15)...
✅ CallManager: Answer already received, stopping API polling  ← 重複防止が動作
✅ CallManager: Processing answer (first time)
🔵 WebRTCService: ICE connection state: connected
```

**ユーザー10（着信側）のログ**:
```
🔍 CallManager: Video track detected in SDP (port: 9)
🔵 CallManager: Call type from SDP: ビデオ通話
✅ CallManager: Answer sent via Socket.io to user 11
✅ CallManager: Answer also saved to API for callId: 11-10
🔵 WebRTCService: ICE connection state: connected
```

---

### テスト3: 音声通話（回帰テスト）

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10に音声通話で発信
3. 応答して音声通話

**期待される結果**:
- ✅ 着信画面が表示
- ✅ 応答後、音声通話画面が表示（ビデオなし）
- ✅ 双方向で音声が聞こえる
- ✅ ログに「No active video track in SDP」が表示される

---

## メッセージ通知の問題（未解決）

### 現状

**アプリ起動中**: ✅ カスタム通知バナーが表示される
**アプリ停止時**: ❌ 音のみで通知バナーが表示されない

### 調査結果

1. **システム設計は正しい**:
   - メッセージ → 通常のAPNs（バナー・音・バッジ）
   - 着信 → VoIP Push（音のみ・アプリ起動）
   - サーバー側のコードも正しく実装されている

2. **トークン登録は正常**:
   - APNsトークン: 登録済み
   - VoIPトークン: 登録済み

3. **考えられる原因**:
   - iOSの通知設定で「バナー」が無効
   - APNs証明書の環境不一致（production vs sandbox）
   - 通知権限の設定

### 確認が必要な項目

#### 1. iOSの通知設定を確認

```
設定 → ChuTalk → 通知
```

以下をすべてONにしてください：
- ✅ **通知を許可**: ON
- ✅ **ロック画面**: ON
- ✅ **通知センター**: ON
- ✅ **バナー**: ON
- ✅ **バナースタイル**: 一時的または持続的
- ✅ **サウンド**: ON
- ✅ **バッジ**: ON

#### 2. アプリ起動時のログを確認

アプリを起動したとき、以下のログが表示されますか？

```
📱 NotificationsService: Authorization status: 2
   Alert: 2
   Badge: 2
   Sound: 2
```

すべて `2` (Authorized)である必要があります。

`0` または `1` の場合、通知権限が許可されていません。

#### 3. メッセージ送信時のサーバーログを確認

ユーザー10がアプリ停止中に、ユーザー11からメッセージを送信したとき、以下のログが表示されますか？

**Signal Server**:
```bash
docker logs -f chutalk_signal | grep -A 5 "message"
```

期待されるログ:
```
[signal] user 10 is offline, sending message push
📨 Sending message Push to user 10
✅ Message Push sent to user 10
```

**API Server**:
```bash
docker logs -f chutalk_api | grep -A 10 "sendMessagePush"
```

期待されるログ:
```
📤 sendMessagePush: Sending to user 10
   Title: [ユーザー11の表示名]
   Body: [メッセージ本文]
📤 sendMessagePush: Sending to token 520d884ea5a55a28...
✅ sendMessagePush: Sent successfully
```

もし「Sent successfully」が表示されない場合、APNsの送信に失敗しています。

---

## まとめ

### 実施した修正

1. ✅ **CallManager.swift**: answerの重複処理を防止
   - `answerReceived`フラグを追加
   - `handleIncomingAnswer()`で重複チェック
   - `pollForAnswer()`でフラグをチェック

2. ✅ **CallManager.swift**: SDPからビデオ判別を改善
   - `detectVideoFromSDP()`メソッドを追加
   - portが0のビデオトラックを無効と判定
   - `a=inactive`属性のビデオトラックを無効と判定

### 期待される効果

1. ✅ **ビデオ通話**: 双方向でビデオ・音声が通じるようになる
2. ✅ **通話確立**: お互い着信を受けて通話できるようになる
3. ✅ **安定性**: WebRTC接続が安定する

### 残る課題

1. ❌ **メッセージ通知（アプリ停止時）**: 通知バナーが表示されない
   - iOSの通知設定を確認する必要がある
   - サーバーログを確認する必要がある

---

**最終更新**: 2025年10月9日 21:00
**次回アクション**:
1. アプリを再ビルド（必須）
2. テスト1を実行（ビデオ通話 - アプリ起動中）
3. テスト2を実行（ビデオ通話 - アプリ停止時）
4. メッセージ通知の設定を確認
5. 結果を報告
