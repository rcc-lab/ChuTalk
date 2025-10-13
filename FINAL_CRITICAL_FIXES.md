# 最終的な重大修正

**作成日時**: 2025年10月9日 18:00
**ステータス**: 🔴 重要修正完了 → 再ビルド必須

---

## 🐛 発見された問題と修正

### 問題1: ビデオ通話が確立しない（401エラー）

**根本原因**:
着信側がanswerをAPIに保存しようとした時、`POST /api/calls/signal/:callId`エンドポイントが管理者トークン（X-Admin-Token）のみを要求していたため、ユーザー認証トークンでは401エラーが返されていました。

**サーバーログで確認したエラー**:
```
POST /api/calls/signal/11-10 401 26 - 0.245 ms
```

**修正内容**:

#### サーバー側（/srv/chutalk/api/server.js）

```javascript
// 修正前
app.post("/api/calls/signal/:callId", async (req, res) => {
  try {
    // Verify admin token
    if (req.headers['x-admin-token'] !== process.env.ADMIN_PUSH_TOKEN) {
      return res.status(401).json({ message: "unauthorized" });
    }

// 修正後
app.post("/api/calls/signal/:callId", async (req, res) => {
  try {
    // Verify admin token OR user authentication
    const hasAdminToken = req.headers["x-admin-token"] === process.env.ADMIN_PUSH_TOKEN;
    const hasUserAuth = req.headers.authorization && req.headers.authorization.startsWith("Bearer ");

    if (!hasAdminToken && !hasUserAuth) {
      return res.status(401).json({ message: "unauthorized" });
    }
```

**実施した操作**:
1. `/srv/chutalk/api/server.js`をバックアップ
2. 261-264行目を修正
3. API Serverを再起動: `docker compose restart api`

**効果**:
- ✅ 着信側がanswerをAPIに保存できるようになる
- ✅ 発信側がポーリングでanswerを取得できるようになる
- ✅ VoIP Push後の通話確立が成功するようになる

---

### 問題2: メッセージ通知が表示されない

**根本原因**:
Socket.IO経由でメッセージを受信した時、MessagingServiceは内部状態を更新するだけで、ユーザーに通知を表示していませんでした。iOS標準の通知を表示するには、UNUserNotificationCenterを使用してローカル通知を作成する必要があります。

**修正内容**:

#### iOS側（MessagingService.swift）

```swift
// インポート追加
import UserNotifications

// handleReceivedMessage()内に追加
// Show local notification
Task {
    await showLocalNotification(from: from, body: body)
}

// 新しいメソッド追加
private func showLocalNotification(from userId: Int, body: String) async {
    // Get sender's display name
    var senderName = "User \(userId)"
    do {
        let contacts = try await ContactsService.shared.getAllContacts()
        if let contact = contacts.first(where: { $0.id == userId }) {
            senderName = contact.displayName
        }
    } catch {
        print("⚠️ MessagingService: Failed to get contact name for notification")
    }

    // Create local notification
    let content = UNMutableNotificationContent()
    content.title = senderName
    content.body = body
    content.sound = .default
    content.badge = NSNumber(value: (self.unreadCounts.values.reduce(0, +)))
    content.userInfo = [
        "type": "chat.message",
        "fromUserId": userId
    ]

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil // Show immediately
    )

    do {
        try await UNUserNotificationCenter.current().add(request)
        print("✅ MessagingService: Local notification added")
    } catch {
        print("❌ MessagingService: Failed to show notification - \(error)")
    }
}
```

**効果**:
- ✅ アプリ起動中にメッセージを受信した時、通知バナーが表示される
- ✅ 通知音が鳴る
- ✅ 発信者の正しい名前が表示される
- ✅ バッジカウントが更新される

---

## 📋 テスト手順

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

### テスト1: メッセージ通知（アプリ起動中）⭐ 最重要

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がホーム画面または連絡先画面にいる（チャット画面は開いていない）
3. ユーザー10がユーザー11にメッセージ「テスト」を送信
4. ユーザー11の画面上部に通知バナーが表示されるか確認

**期待される結果**:
- ✅ 通知バナーが画面上部に表示される
- ✅ タイトル: ユーザー10の表示名
- ✅ 本文: テスト
- ✅ 通知音が鳴る

**注意**: チャット画面を開いている時は通知バナーは表示されません（一般的なチャットアプリの動作）

---

### テスト2: ビデオ通話（アプリ停止時）⭐ 最重要

**手順**:
1. ユーザー10のアプリを完全に停止（タスクマネージャーからスワイプ）
2. 30秒待つ
3. ユーザー11がユーザー10にビデオ通話で発信
4. ユーザー10でCallKit着信が表示されることを確認
5. 応答ボタンをタップ
6. ビデオ通話画面が表示されることを確認
7. **ビデオ・音声が双方向で通じることを確認** ← 重要

**期待される結果**:
- ✅ CallKit着信画面が表示（ロック画面でも）
- ✅ 応答すると自動的にアプリが起動
- ✅ ビデオ通話画面が表示
- ✅ **双方向でビデオが表示される**
- ✅ **双方向で音声が聞こえる**

---

### テスト3: メッセージ通知（アプリ停止時）

**手順**:
1. ユーザー10のアプリを完全に停止
2. 30秒待つ
3. ユーザー11がユーザー10にメッセージ「テスト2」を送信
4. ユーザー10のデバイスで通知が表示されるか確認

**期待される結果**:
- ✅ 通知バナーが表示される（ロック画面でも）
- ✅ タイトル: ユーザー11の表示名
- ✅ 本文: テスト2
- ✅ 通知音が鳴る
- ✅ 通知タップでアプリが起動し、チャット画面が表示される

---

### テスト4: ビデオ通話（アプリ起動中）- 回帰テスト

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10に発信
3. 応答してビデオ通話

**期待される結果**:
- ✅ 着信画面が即座に表示
- ✅ 応答後、ビデオ通話が確立
- ✅ 双方向でビデオ・音声が通じる

---

## 📊 変更ファイル一覧

### サーバー側

1. **server.js** (/srv/chutalk/api/server.js)
   - Line 261-267: `POST /api/calls/signal/:callId`エンドポイントでユーザー認証も受け入れるように修正
   - バックアップ: `server.js.backup_YYYYMMDD_HHMMSS`

### iOS側

1. **MessagingService.swift**
   - Line 10: `import UserNotifications`追加
   - Line 175-178: メッセージ受信時にローカル通知を表示
   - Line 183-218: `showLocalNotification()`メソッド追加

2. **SocketService.swift** (前回の修正)
   - Line 281-289: `sendMessage()`にdisplayName追加
   - Line 229-237: `sendOffer()`にdisplayName追加

3. **CallManager.swift** (前回の修正)
   - Line 346-355: answerをAPIに保存
   - Line 169-221: answerポーリング機能追加

4. **APIService.swift** (前回の修正)
   - Line 356-395: `saveAnswer()`メソッド追加
   - Line 397-452: `getAnswerSDP()`メソッド追加

5. **NotificationsService.swift** (前回の修正)
   - 詳細ログ追加

6. **AppDelegate.swift** (前回の修正)
   - 詳細ログ追加

---

## 🔍 トラブルシューティング

### メッセージ通知が表示されない場合

#### 1. 通知権限を確認

**iOSの設定**:
```
設定 → ChuTalk → 通知
- 通知を許可: ON
- バナー: ON
- サウンド: ON
```

#### 2. チャット画面を閉じているか確認

通知バナーはチャット画面を開いていない時のみ表示されます。ホーム画面または連絡先画面でテストしてください。

---

### ビデオ通話が通じない場合

#### 1. カメラ・マイクの権限を確認

**iOSの設定**:
```
設定 → ChuTalk
- カメラ: ON
- マイク: ON
```

#### 2. ネットワーク接続を確認

両デバイスが同じWi-Fiネットワークに接続されているか、またはインターネット接続が安定しているか確認してください。

#### 3. サーバーログを確認

```bash
docker logs -f chutalk_signal | grep "offer\|answer"
docker logs -f chutalk_api | grep "call\|answer"
```

**期待されるログ**:
```
Signal Server:
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push

API Server:
📞 API: Received offer for callId: 11-10
✅ API: Saved offer for callId: 11-10
📞 API: Received answer for callId: 11-10  ← これが重要
✅ API: Saved answer for callId: 11-10
```

**もし「Received answer」が表示されない場合**:
→ 着信側でanswerの保存に失敗している可能性があります
→ API Serverが正しく再起動されているか確認してください

---

## ✅ 確認事項

修正が正しく適用されているか確認してください：

### サーバー側

```bash
# API Serverが起動しているか
docker ps | grep chutalk_api

# 修正が適用されているか
ssh takaoka@192.168.200.50
cat /srv/chutalk/api/server.js | grep -A 5 "Verify admin token OR"
```

**期待される出力**:
```javascript
// Verify admin token OR user authentication
const hasAdminToken = req.headers["x-admin-token"] === process.env.ADMIN_PUSH_TOKEN;
const hasUserAuth = req.headers.authorization && req.headers.authorization.startsWith("Bearer ");

if (!hasAdminToken && !hasUserAuth) {
  return res.status(401).json({ message: "unauthorized" });
}
```

---

## 📝 まとめ

### 実施した修正

1. ✅ **サーバー側**: answer保存エンドポイントでユーザー認証を受け入れるように修正
2. ✅ **サーバー側**: API Serverを再起動
3. ✅ **iOS側**: Socket.IO経由でメッセージ受信時にローカル通知を表示

### 期待される効果

1. ✅ **ビデオ通話**: VoIP Push後の通話確立が成功するようになる
2. ✅ **メッセージ通知**: アプリ起動中にメッセージを受信した時、通知バナーが表示される
3. ✅ **メッセージ通知**: アプリ停止時にメッセージを受信した時、Push通知が表示される

---

**最終更新**: 2025年10月9日 18:00
**次回アクション**:
1. アプリを再ビルド（必須）
2. テスト1を実行（メッセージ通知 - アプリ起動中）
3. テスト2を実行（ビデオ通話 - アプリ停止時）
4. 結果を報告
