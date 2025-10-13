# 着信が鳴らない問題の解決

## 問題の原因

着信が検出されない根本的な原因は、**APIエンドポイントの不一致**でした。

### 修正前の動作

**オファー送信時（User 11 → User 10）:**
```
POST /api/calls/signal
Body: {
  "callId": "11-10",
  "action": "offer",
  "data": {"sdp": "..."}
}
```

**着信チェック時（User 10）:**
```
GET /api/calls/signal/11-10
```

callIdがPOSTではリクエストボディ内にあり、GETではURLパスにあるため、サーバー側で保存場所と取得場所が一致せず、シグナルが見つからない状態でした。

## 修正内容

**ファイル:** `ChuTalk/Services/APIService.swift`

**変更箇所:** `sendSignal` 関数（233-244行目）

### 修正前
```swift
func sendSignal(callId: String, action: String, data: [String: Any]) async throws {
    struct EmptyResponse: Codable {}
    let _: EmptyResponse = try await request(
        url: Constants.API.callSignal,  // "/api/calls/signal"
        method: "POST",
        body: [
            "callId": callId,  // ❌ ボディに含まれている
            "action": action,
            "data": data
        ],
        requiresAuth: true
    )
}
```

### 修正後
```swift
func sendSignal(callId: String, action: String, data: [String: Any]) async throws {
    struct EmptyResponse: Codable {}
    let _: EmptyResponse = try await request(
        url: "\(Constants.API.callSignal)/\(callId)",  // ✅ URLパスに含める
        method: "POST",
        body: [
            "action": action,
            "data": data
        ],
        requiresAuth: true
    )
}
```

## 修正後の動作

**オファー送信時（User 11 → User 10）:**
```
POST /api/calls/signal/11-10
Body: {
  "action": "offer",
  "data": {"sdp": "..."}
}
```

**着信チェック時（User 10）:**
```
GET /api/calls/signal/11-10
```

これで送信と受信で同じエンドポイント形式を使用するため、シグナルが正しく保存・取得されます。

## 期待される結果

この修正により、以下のログが表示されるようになります：

```
// User 11が発信
🔵 CallManager: Starting call to User 10
🔵 CallManager: Call ID: 11-10
✅ CallManager: Offer sent via API to User 10

// User 10が着信検出
🔍 NotificationService: 着信チェック開始 - User ID: 10
🔍 NotificationService: Checked callId 11-10 - Status: 200
🔍 NotificationService: Response: [{"action":"offer","data":{"sdp":"..."}}]
🔍 NotificationService: Signals found for callId 11-10: 1 signals
🔍 NotificationService: Signal action: offer
📞 NotificationService: 着信検出！ CallID: 11-10
📞 NotificationService: 発信者: 11 → 着信者: 10
📞 NotificationService: Calling CallKitService.reportIncomingCall

// CallKitが着信UI表示
📞 CallKitService: ========== INCOMING CALL ==========
📞 CallKitService: Handle: User 11
✅ CallKitService: Incoming call reported successfully
✅ CallKitService: CallKit UI should be visible now
```

## テスト手順

1. **アプリをビルドして実機にインストール**
   - Xcodeでプロジェクトを開く
   - 実機を接続
   - Product → Run でビルド

2. **2台の端末で準備**
   - 端末1: User 10でログイン
   - 端末2: User 11でログイン

3. **着信テスト**
   - User 11からUser 10に発信
   - User 10でCallKitの着信画面が表示されることを確認
   - 着信音が鳴ることを確認
   - 「応答」をタップして通話が開始されることを確認

4. **Xcodeコンソールでログ確認**
   - 上記の「期待される結果」のログが表示されることを確認
   - 特に `found signals: 1` が表示されることを確認（以前は `found signals: 0` だった）

## トラブルシューティング

もし着信がまだ鳴らない場合：

1. **キャッシュをクリア**
   - Product → Clean Build Folder
   - アプリを削除して再インストール

2. **認証トークンを確認**
   ```
   ✅ NotificationService: Starting monitoring for user 10
   ```
   このログが表示されることを確認

3. **ネットワーク接続を確認**
   - APIサーバーに接続できることを確認
   - Wi-Fiまたはモバイルデータが有効

4. **デバイス設定を確認**
   - 消音モードOFF
   - 音量が0でない
   - おやすみモードOFF

## 次のステップ

この修正で着信が正常に動作するようになります。次の機能として：

1. **バックグラウンド通知**
   - アプリが閉じている時の着信通知
   - VoIP Push通知の実装（サーバー側の対応が必要）

2. **メッセージ通知**
   - アプリが閉じている時のメッセージ通知
   - APNs通知の実装（サーバー側の対応が必要）

現在はアプリが開いている時のみ着信・メッセージ通知が機能します。
バックグラウンド対応はサーバー側でPush通知の送信機能を実装する必要があります。
