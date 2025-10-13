# 通知問題のデバッグ手順

**重要**: 以下の手順を順番に実施し、各ステップのログを確認してください。

---

## ステップ1: アプリ起動時のログ確認

### 手順

1. Xcodeで**両デバイス**のアプリを再ビルド・起動
2. 起動直後のログを確認

### 確認するログ

```
📱 NotificationsService: Authorization status: ?
   Alert: ?
   Badge: ?
   Sound: ?
```

**期待される値**: すべて `2` (Authorized)

**もし `0` または `1` の場合**:
→ iOSの設定で通知権限を確認
```
設定 → ChuTalk → 通知 → 通知を許可: ON
設定 → ChuTalk → 通知 → バナー: ON
設定 → ChuTalk → 通知 → サウンド: ON
```

### ログをここに貼り付けてください

```
[ステップ1のログをここに貼り付け]
```

---

## ステップ2: メッセージ送信テスト（アプリ起動中）

### 手順

1. **両デバイスでアプリを起動したまま**
2. ユーザー11がユーザー10にメッセージ「テスト」を送信
3. ユーザー10でメッセージが届くか確認
4. **通知バナーが表示されるか確認**

### ユーザー11（送信側）のログを確認

```
🔵 SocketService: Sending message to 10
✅ SocketService: Message emit completed
```

### ユーザー10（受信側）のログを確認

**パターンA: 通知バナーが表示された場合**
```
📨 NotificationsService: ========== FOREGROUND NOTIFICATION ==========
📨 NotificationsService: Title: [発信者名]
📨 NotificationsService: Body: テスト
```

**パターンB: 通知バナーが表示されない場合**
```
🔵 SocketService: message event - [...]
✅ SocketService: Received message from 11
```
→ Socket.IO経由でメッセージは届いているが、通知バナーが表示されていない

### ログをここに貼り付けてください

**ユーザー11（送信側）**:
```
[送信側のログをここに貼り付け]
```

**ユーザー10（受信側）**:
```
[受信側のログをここに貼り付け]
```

### 確認: 通知バナーは表示されましたか？

- [ ] はい、表示された
- [ ] いいえ、表示されなかった

---

## ステップ3: メッセージ送信テスト（アプリ停止時）

### 手順

1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. **30秒待つ**
3. ユーザー11がユーザー10にメッセージ「テスト2」を送信
4. ユーザー10のデバイスで通知が表示されるか確認

### サーバーログを確認

**Signal Server**:
```bash
docker logs -f chutalk_signal | grep -A 5 "message"
```

**期待されるログ**:
```
[signal] user 10 is offline, sending message push
📨 Sending message Push to user 10
✅ Message Push sent to user 10
```

**API Server**:
```bash
docker logs -f chutalk_api | grep -A 10 "sendMessagePush"
```

**期待されるログ**:
```
📤 sendMessagePush: Sending to user 10
   Title: [ユーザー11の表示名]
   Body: テスト2
📤 sendMessagePush: Sending to token 520d884ea5a55a28...
✅ sendMessagePush: Sent successfully
```

### ログをここに貼り付けてください

**Signal Serverログ**:
```
[Signal Serverのログをここに貼り付け]
```

**API Serverログ**:
```
[API Serverのログをここに貼り付け]
```

### 確認: 通知は表示されましたか？

- [ ] はい、表示された
- [ ] いいえ、表示されなかった

### もし表示されなかった場合

ユーザー10のアプリを起動し、以下のログを確認:

```
📨 AppDelegate: ========== REMOTE NOTIFICATION ==========
📨 AppDelegate: Application state: ?
```

このログが表示される場合 → Push通知は届いているが、表示されていない
このログが表示されない場合 → Push通知が届いていない

---

## ステップ4: ビデオ通話テスト（アプリ停止時）

### 手順

1. ユーザー10のアプリを完全に停止
2. 30秒待つ
3. ユーザー11がユーザー10に**ビデオ通話**で発信
4. ユーザー10でCallKit着信が表示されるか確認
5. 応答ボタンをタップ
6. **応答後のログを確認**

### ユーザー11（発信側）のログを確認

```
✅ CallManager: Offer sent via Socket.io to User 10
🔍 CallManager: Polling API for answer (attempt 1/15)...
🔍 CallManager: Polling API for answer (attempt 2/15)...
✅ CallManager: Found answer in API! Processing...
✅ CallManager: Received answer
```

### ユーザー10（着信側）のログを確認

**VoIP Push受信時**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: [...]
📞 CallKitProvider: reportIncomingCall
```

**応答後**:
```
📞 ContentView: ========== CALLKIT ANSWER ==========
✅ ContentView: Found offer SDP
📞 CallManager: Accepting incoming call
✅ CallManager: Answer also saved to API
🎥 WebRTCService: Setting up local tracks - isVideo: true
✅ WebRTCService: Audio track added
✅ WebRTCService: Video track added
```

**重要**: 以下のログを確認
```
🔵 WebRTCService: ICE connection state: checking
🔵 WebRTCService: ICE connection state: connected  ← これが表示されるべき
```

### ログをここに貼り付けてください

**ユーザー11（発信側）**:
```
[発信側のログをここに貼り付け]
```

**ユーザー10（着信側）**:
```
[着信側のログをここに貼り付け]
```

### 確認項目

1. CallKit着信は表示されましたか？
   - [ ] はい
   - [ ] いいえ

2. 応答後、ビデオ通話画面は表示されましたか？
   - [ ] はい
   - [ ] いいえ

3. 「ICE connection state: connected」は表示されましたか？
   - [ ] はい
   - [ ] いいえ

4. ビデオ・音声は通じましたか？
   - [ ] はい
   - [ ] いいえ

---

## ステップ5: APNsトークン確認

### サーバーで確認

```bash
docker exec chutalk_db psql -U postgres -d chutalk -c \
  "SELECT user_id, LEFT(apns_token, 20), LEFT(voip_token, 20), bundle_id FROM devices WHERE user_id IN (10, 11);"
```

### ログをここに貼り付けてください

```
[DBクエリ結果をここに貼り付け]
```

### 確認

- APNsトークンとVoIPトークンの両方が登録されているか
- bundle_idが正しいか（`rcc.takaokanet.com.ChuTalk`）

---

## ステップ6: 通知設定の確認（iOS）

### ユーザー10のデバイスで確認

```
設定 → ChuTalk
```

以下をスクリーンショットで撮影してください：

1. **通知設定**
   - 通知を許可: ?
   - ロック画面: ?
   - 通知センター: ?
   - バナー: ?
   - バナースタイル: ?
   - サウンド: ?
   - バッジ: ?

2. **その他の権限**
   - カメラ: ?
   - マイク: ?

---

## まとめ

すべてのステップが完了したら、以下の情報を送ってください：

1. ステップ1のログ（通知権限の状態）
2. ステップ2のログ（メッセージ送信 - アプリ起動中）
3. ステップ3のログ（メッセージ送信 - アプリ停止時）+ サーバーログ
4. ステップ4のログ（ビデオ通話 - アプリ停止時）
5. ステップ5のログ（APNsトークン）
6. ステップ6のスクリーンショット（通知設定）

これらの情報があれば、問題の原因を特定できます。
