# メッセージ通知とビデオ通話の修正

**作成日時**: 2025年10月9日 17:30
**ステータス**: 修正完了 → テスト待ち

---

## 修正内容

### 1. ✅ メッセージ通知の修正

**問題**: メッセージ通知が表示されない

**原因**: iOS側からメッセージを送信する時、発信者の`displayName`を含めていなかったため、サーバー側でデフォルト値「User X」が使われていた。また、offerにも`displayName`が含まれていなかった。

**修正**: SocketService.swiftの`sendMessage()`と`sendOffer()`に`displayName`を追加

**変更ファイル**: SocketService.swift

```swift
// sendMessage() - Line 274
func sendMessage(to userId: Int, body: String) {
    // Get current user's display name for push notifications
    let displayName = AuthService.shared.currentUser?.displayName ?? "Unknown"

    socket?.emit(Constants.SocketEvents.message, [
        "to": userId,
        "body": body,
        "displayName": displayName  // ← 追加
    ])
}

// sendOffer() - Line 222
func sendOffer(to userId: Int, sdp: String) {
    // Get current user's display name for VoIP push notifications
    let displayName = AuthService.shared.currentUser?.displayName ?? "Unknown"

    socket?.emit(Constants.SocketEvents.offer, [
        "to": userId,
        "sdp": sdp,
        "displayName": displayName  // ← 追加
    ])
}
```

**効果**:
- メッセージPush通知に正しい発信者名が表示される
- VoIP Push通知に正しい発信者名が表示される

---

### 2. ✅ 通知ログの強化

**目的**: 通知が正しく送信・受信されているか詳細に確認できるようにする

**変更ファイル**:
- NotificationsService.swift
- AppDelegate.swift

**追加したログ**:

#### NotificationsService.swift

```swift
// checkAuthorizationStatus() - 通知権限の状態を出力
print("📱 NotificationsService: Authorization status: \(settings.authorizationStatus.rawValue)")
print("   Alert: \(settings.alertSetting.rawValue)")
print("   Badge: \(settings.badgeSetting.rawValue)")
print("   Sound: \(settings.soundSetting.rawValue)")

// willPresent() - フォアグラウンド通知受信時
print("📨 NotificationsService: ========== FOREGROUND NOTIFICATION ==========")
print("📨 NotificationsService: Title: \(notification.request.content.title)")
print("📨 NotificationsService: Body: \(notification.request.content.body)")
// ... 詳細ログ

// didReceive() - 通知タップ時
print("📨 NotificationsService: ========== NOTIFICATION TAPPED ==========")
print("📨 NotificationsService: Action: \(response.actionIdentifier)")
// ... 詳細ログ
```

#### AppDelegate.swift

```swift
// didReceiveRemoteNotification() - リモート通知受信時
print("📨 AppDelegate: ========== REMOTE NOTIFICATION ==========")
print("📨 AppDelegate: Application state: \(application.applicationState.rawValue)")
print("📨 AppDelegate: UserInfo: \(userInfo)")
// ... 詳細ログ
```

---

### 3. ✅ ビデオ通話画面の表示問題を解決

**進捗**: ユーザーからの報告により、VoIP Push後にビデオ通話画面が表示されるようになったことを確認

これは、前回の修正（Answer送信の二重化 + Answerポーリング）が正しく機能していることを示しています。

**現在の状態**:
- ✅ VoIP Push受信 → CallKit表示 → 応答 → ビデオ通話画面表示
- ⚠️ ビデオ/音声が通じない（次の調査項目）

---

## 📋 テスト手順

### テスト1: メッセージ通知（アプリ停止時）

**手順**:
1. アプリを再ビルド・再インストール
2. 両デバイスでログイン
3. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプ）
4. **30秒待つ**
5. ユーザー11がユーザー10にメッセージを送信
6. ユーザー10のデバイスで通知が表示されるか確認

**期待される結果**:
- ✅ 通知バナーが表示される
- ✅ 通知に発信者名（ユーザー11の表示名）が表示される
- ✅ 通知音が鳴る
- ✅ 通知タップでアプリが起動し、メッセージが表示される

**サーバーログ（Signal Server）**:
```bash
docker logs -f chutalk_signal
```

**期待されるログ**:
```
[signal] user 10 is offline, sending message push
📨 Sending message Push to user 10
✅ Message Push sent to user 10
```

**サーバーログ（API Server）**:
```bash
docker logs -f chutalk_api
```

**期待されるログ**:
```
📤 sendMessagePush: Sending to user 10
   Title: ユーザー11の表示名
   Body: メッセージ内容
📤 sendMessagePush: Sending to token 520d884ea5a55a28...
✅ sendMessagePush: Sent successfully
POST /api/internal/push/message 200
```

**Xcodeログ（ユーザー10 - 通知タップ後）**:
```
📨 NotificationsService: ========== NOTIFICATION TAPPED ==========
📨 NotificationsService: Type: chat.message
```

---

### テスト2: メッセージ通知（アプリ起動時）

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10にメッセージを送信

**期待される結果**:
- ✅ メッセージが即座にチャット画面に表示される
- ✅ Socket.IO経由で受信される（Push通知は送信されない）

---

### テスト3: ビデオ通話（アプリ停止時）

**手順**:
1. ユーザー10のアプリを完全に停止
2. 30秒待つ
3. ユーザー11がユーザー10に発信
4. ユーザー10でCallKit着信が表示されることを確認
5. 応答ボタンをタップ
6. ビデオ通話画面が表示されることを確認
7. **ビデオ・音声が通じるか確認** ← 重要

**期待される結果**:
- ✅ CallKit着信画面が表示（発信者名が正しく表示される）
- ✅ 応答すると自動的にアプリが起動
- ✅ ビデオ通話画面が表示
- ✅ 双方向でビデオ・音声が通じる ← 要確認

**Xcodeログを確認**（ビデオ・音声が通じない場合）:

**発信者側（ユーザー11）**:
```
✅ CallManager: Offer sent via Socket.io
✅ CallManager: Found answer in API! Processing...
✅ CallManager: Received answer
🔵 WebRTCService: ICE connection state: checking
🔵 WebRTCService: ICE connection state: connected  ← これが重要
```

**着信者側（ユーザー10）**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
✅ ContentView: Found offer SDP
✅ CallManager: Answer also saved to API
🎥 WebRTCService: Setting up local tracks - isVideo: true
✅ WebRTCService: Audio track added
✅ WebRTCService: Video track added
🔵 WebRTCService: ICE connection state: checking
🔵 WebRTCService: ICE connection state: connected  ← これが重要
```

---

## 🐛 トラブルシューティング

### メッセージ通知が表示されない場合

#### 1. 通知権限を確認

**Xcodeログで確認**:
```
📱 NotificationsService: Authorization status: 2
   Alert: 2
   Badge: 2
   Sound: 2
```

- `2` = Authorized（許可）
- `0` = NotDetermined（未決定）
- `1` = Denied（拒否）

**許可されていない場合**:
```
設定 → ChuTalk → 通知 → 通知を許可: ON
```

#### 2. APNsトークンを確認

**サーバーで確認**:
```bash
docker exec chutalk_db psql -U postgres -d chutalk -c \
  "SELECT user_id, LEFT(apns_token, 20) FROM devices WHERE user_id=10;"
```

**期待される結果**:
```
 user_id |         left
---------+----------------------
      10 | 520d884ea5a55a281bde
```

**トークンがない場合**:
- アプリを再起動
- ログインし直す

#### 3. サーバーログを確認

**Signal Server**:
```bash
docker logs -f chutalk_signal | grep -i "message"
```

**期待されるログ**:
```
[signal] user 10 is offline, sending message push
```

**API Server**:
```bash
docker logs -f chutalk_api | grep -i "message"
```

**期待されるログ**:
```
📤 sendMessagePush: Sending to user 10
✅ sendMessagePush: Sent successfully
```

**エラーがある場合**:
```
❌ sendMessagePush: Failed: ...
```
→ APNs証明書や環境変数の設定を確認

---

### ビデオ・音声が通じない場合

#### 1. WebRTC接続状態を確認

**Xcodeログで「ICE connection state: connected」を確認**:
```
🔵 WebRTCService: ICE connection state: checking
🔵 WebRTCService: ICE connection state: connected  ← これが表示されるべき
```

**「connected」にならない場合**:
- ネットワーク接続を確認
- Wi-Fi接続を確認
- STUN/TURNサーバーの設定を確認

#### 2. カメラ・マイクの権限を確認

**iOSの設定で確認**:
```
設定 → ChuTalk → カメラ: ON
設定 → ChuTalk → マイク: ON
```

#### 3. ローカル/リモートビデオトラックを確認

**Xcodeログで確認**:
```
✅ WebRTCService: Audio track added
✅ WebRTCService: Video track added
🎥 WebRTCService: Remote stream added
```

**トラックが追加されていない場合**:
- WebRTCServiceの初期化に問題がある可能性
- アプリを再起動して再テスト

---

## 📊 変更ファイル一覧

### 修正したファイル

1. **SocketService.swift**
   - `sendMessage()`: displayNameを追加
   - `sendOffer()`: displayNameを追加

2. **NotificationsService.swift**
   - `checkAuthorizationStatus()`: ログ強化
   - `willPresent()`: ログ強化
   - `didReceive()`: ログ強化

3. **AppDelegate.swift**
   - `didReceiveRemoteNotification()`: ログ強化

---

## ✅ 次のステップ

1. **アプリを再ビルド** ← 必須
   ```
   Product → Clean Build Folder (Shift + Cmd + K)
   Product → Build (Cmd + B)
   Product → Run (Cmd + R)
   ```

2. **テスト1を実行**（メッセージ通知）
   - 成功: サーバーログとXcodeログを確認
   - 失敗: トラブルシューティング参照

3. **テスト3を実行**（ビデオ通話）
   - ビデオ通話画面が表示されるか確認
   - **ビデオ・音声が通じるか確認** ← 最重要
   - 通じない場合: Xcodeログで「ICE connection state」を確認

4. **結果を報告**:
   - どのテストが成功したか
   - どのテストで失敗したか
   - Xcodeログ（特にICE connection state）
   - サーバーログ

---

**最終更新**: 2025年10月9日 17:30
**次回アクション**: アプリ再ビルド → テスト実施 → 結果報告
