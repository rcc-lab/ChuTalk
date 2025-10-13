# メッセージ通知の根本的な修正

**作成日時**: 2025年10月9日 23:30
**ステータス**: ✅ 修正完了 → 再ビルド必須

---

## 問題の根本原因

### 症状

- アプリ起動中: ✅ カスタム通知バナーが表示される
- アプリ停止時: ❌ 通知が全く来ない（音もバイブもバナーもなし）

### 原因の特定

**サーバーログの分析結果**:
```
# メッセージイベントが全く記録されていない
docker logs chutalk_signal | grep "message"
→ 結果: 0件

# ビデオ通話イベントは記録されている
docker logs chutalk_signal | grep "offer"
→ 結果: 多数
```

**結論**: **iOS側からSocket.IO経由でメッセージが送信されていなかった**

---

## 現在の実装（修正前）

### iOS側: MessagingService.swift

```swift
func sendMessage(to userId: Int, content: String) async -> Bool {
    // メッセージをAPIに保存（HTTP）
    let message = try await APIService.shared.sendMessage(receiverId: userId, body: content)

    // ローカルに保存
    conversations[userId]?.append(message)

    // ❌ Socket.IOには送信していない
    return true
}
```

### 結果

1. **API Serverにメッセージが保存される**（HTTP）
2. **Signal Serverには送信されない**（Socket.IOを使っていない）
3. 受信側がアプリ起動中の場合:
   - NotificationServiceのポーリングで検出 → ✅ 動作
4. 受信側がアプリ停止中の場合:
   - Signal Serverがメッセージを知らない → ❌ Push通知が送信されない

---

## 修正内容

### MessagingService.swift (Line 109-111)

**追加したコード**:
```swift
// Also send via Socket.IO for real-time delivery and push notifications
SocketService.shared.sendMessage(to: userId, body: content)
print("✅ MessagingService: Sent message via Socket.IO to \(userId)")
```

**完全な修正後のコード**:
```swift
func sendMessage(to userId: Int, content: String) async -> Bool {
    guard let currentUserId = AuthService.shared.currentUser?.id else {
        print("❌ MessagingService: No current user")
        return false
    }

    print("📤 MessagingService: Attempting to send message to user \(userId)")
    print("📤 MessagingService: Message content: \(content)")

    do {
        // 1. APIにメッセージを保存
        let message = try await APIService.shared.sendMessage(receiverId: userId, body: content)

        await MainActor.run {
            // 2. ローカルに保存
            if self.conversations[userId] == nil {
                self.conversations[userId] = []
            }
            self.conversations[userId]?.append(message)
            LocalStorageManager.shared.addMessage(message)
            print("✅ MessagingService: Sent message via API to \(userId)")

            // 3. Socket.IO経由でSignal Serverに送信（新規追加）
            SocketService.shared.sendMessage(to: userId, body: content)
            print("✅ MessagingService: Sent message via Socket.IO to \(userId)")
        }
        return true
    } catch {
        // エラー処理...
    }
}
```

---

## 修正後の動作フロー

### ケース1: 受信側がアプリ起動中

```
ユーザー11がメッセージ送信
    ↓
MessagingService.sendMessage()
    ↓
1. API Serverにメッセージ保存（HTTP）
2. Socket.IO経由でSignal Serverに送信（新規）
    ↓
Signal Server: ユーザー10はオンライン
    ↓
Socket.IO経由で即座に配信
    ↓
ユーザー10のSocketService.onMessageReceived
    ↓
MessagingService.handleReceivedMessage()
    ↓
NotificationCenter.post(.newMessageReceived)
    ↓
ContentView: カスタムバナー表示
```

### ケース2: 受信側がアプリ停止中（修正済み）

```
ユーザー11がメッセージ送信
    ↓
MessagingService.sendMessage()
    ↓
1. API Serverにメッセージ保存（HTTP）
2. Socket.IO経由でSignal Serverに送信（新規）
    ↓
Signal Server: ユーザー10はオフライン
    ↓
API Serverの sendMessagePush() を呼び出し（新規）
    ↓
APNs経由でPush通知を送信
    ↓
ユーザー10のiPhoneに通知バナーが表示される ✅
```

---

## 期待される効果

### 修正前

| 状況 | 通知 | メカニズム |
|------|------|------------|
| アプリ起動中 | ✅ カスタムバナー | NotificationServiceのポーリング |
| アプリ停止中 | ❌ なし | Socket.IOを使っていないため |

### 修正後

| 状況 | 通知 | メカニズム |
|------|------|------------|
| アプリ起動中 | ✅ カスタムバナー | Socket.IO経由でリアルタイム配信 |
| アプリ停止中 | ✅ iOS標準バナー | Signal Server → APNs経由でPush通知 |

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

**2. サーバーログ監視を開始**

ターミナル1:
```bash
ssh takaoka@192.168.200.50
docker logs -f chutalk_signal 2>&1 | grep --line-buffered -E "message|user.*offline"
```

ターミナル2:
```bash
ssh takaoka@192.168.200.50
docker logs -f chutalk_api 2>&1 | grep --line-buffered "sendMessagePush" -A 5
```

---

### テスト1: メッセージ通知（アプリ停止時）⭐ 最重要

**手順**:
1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. **1分間待つ**（Socket.IO接続が完全に切れるまで）
3. ユーザー11からユーザー10にメッセージ「テストメッセージ」を送信

**期待されるサーバーログ（Signal Server）**:
```
[signal] message event received
[signal] user 10 is offline, sending message push
📨 Sending message Push to user 10
```

**期待されるサーバーログ（API Server）**:
```
📤 sendMessagePush: Sending to user 10
   Title: [ユーザー11の表示名]
   Body: テストメッセージ
📤 sendMessagePush: Sending to token 520d884ea5a55a28...
✅ sendMessagePush: Sent successfully
```

**期待されるユーザー10のデバイス**:
- ✅ iOS標準の通知バナーが表示される
- ✅ 通知音が鳴る
- ✅ バイブが振動する
- ✅ ロック画面にも表示される

---

### テスト2: メッセージ通知（アプリ起動中）

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー10がホーム画面にいる（チャット画面ではない）
3. ユーザー11からメッセージ送信

**期待される動作**:
- ✅ カスタム通知バナー（青い背景）が表示される
- ✅ 音が鳴る

**期待されるログ（ユーザー11側）**:
```
✅ MessagingService: Sent message via API to 10
✅ MessagingService: Sent message via Socket.IO to 10
```

---

### テスト3: リアルタイムメッセージ配信

**手順**:
1. 両デバイスでアプリを起動
2. 両方ともチャット画面を開く
3. ユーザー11からメッセージ送信

**期待される動作**:
- ✅ ユーザー10のチャット画面に即座にメッセージが表示される
- ✅ ポーリングを待たずに、Socket.IO経由でリアルタイム配信

---

## トラブルシューティング

### Q1: まだ通知が表示されない

**A**: 以下を確認してください:

1. **アプリを再ビルドしましたか？**
   - 必ず Clean Build Folder してから再ビルド

2. **サーバーログで「sendMessagePush」が表示されますか？**
   - 表示される → APNsの問題（iOSの設定、トークン登録など）
   - 表示されない → Socket.IO接続の問題

3. **Signal Serverで「message」イベントが記録されますか？**
   ```bash
   docker logs -f chutalk_signal | grep "message"
   ```
   - 表示される → 修正が適用されています
   - 表示されない → アプリが再ビルドされていません

---

### Q2: ビデオ通話は着信するのに、メッセージは通知が来ない

**A**: APNsの設定は正しいです。Socket.IOの接続を確認してください:

1. アプリ起動時のログで以下を確認:
   ```
   ✅ SocketService: Connected to signal server
   ✅ SocketService: Registered user: [ユーザーID]
   ```

2. もし接続されていない場合:
   - アプリを再起動
   - Signal Serverの起動を確認: `docker ps | grep signal`

---

## まとめ

### 問題の本質

**メッセージ送信がSocket.IOを使っていなかった**ため、Signal Serverがメッセージを知らず、受信側がオフラインの時にPush通知を送信できなかった。

### 修正内容

MessagingService.sendMessage()に、Socket.IO経由の送信を追加した。これにより：
1. リアルタイム配信が可能になる
2. 受信側がオフラインの時、Signal ServerがAPNs経由でPush通知を送信する

### 期待される効果

- ✅ アプリ停止時にメッセージPush通知が表示される
- ✅ アプリ起動中はSocket.IO経由でリアルタイム配信される
- ✅ ポーリングに依存しない、即座なメッセージ配信

---

**最終更新**: 2025年10月9日 23:30
**次回アクション**:
1. アプリを再ビルド（必須）
2. テスト1を実行（アプリ停止時）
3. サーバーログを確認
4. 結果を報告
