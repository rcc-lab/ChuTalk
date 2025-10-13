# 最終修正とテスト計画

**作成日時**: 2025年10月9日 16:30
**ステータス**: ✅ すべての修正完了 → 📋 テスト待ち

---

## 📌 今回の修正内容

### 1. ✅ Socket.IO パス不一致の修正（完了）

**問題**: Signal Serverのパス設定が間違っていたため、Socket.IO接続が全く機能していなかった。

**修正**:
```yaml
# docker-compose.yml
signal:
  environment:
    SOCKETIO_PATH: /socket.io/  # ← /signal/socket.io/ から変更
```

**結果**: ✅ 両ユーザーでSocket.IO接続成功を確認済み

---

### 2. ✅ 古いポーリング機構の無効化（完了）

**問題**: Socket.IOが動作していなかった時期に作成された「ポーリング方式の着信検出」が、Socket.IO + VoIP Push の正しいフローを妨害していた。

**修正**:
```swift
// ContentView.swift Line 128
// DISABLED: Old polling mechanism - no longer needed with Socket.IO + VoIP Push
// notificationService.startMonitoring(userId: userId)
print("✅ ContentView: Using Socket.IO + VoIP Push instead of polling")
```

**理由**:
- Socket.IOが正常に動作するようになったため、ポーリングは不要
- ポーリングがVoIP Pushの正しい動作を妨害する可能性がある
- 1秒ごとのAPIリクエストによるサーバー負荷を削減

---

### 3. ✅ VoIP Push実装の確認（完了）

**確認項目**:
- [x] Signal Server: offer検出時にVoIP Push送信 → ✅ 実装済み
- [x] API Server: VoIP Push送信エンドポイント → ✅ 実装済み
- [x] push.js: APNs送信ロジック → ✅ 正しく実装
- [x] VoIPPushService.swift: iOS側の受信処理 → ✅ 正しく実装
- [x] AppDelegate.swift: VoIP登録 → ✅ 正しく実装
- [x] APNs設定: 環境変数とP8証明書 → ✅ 設定済み
- [x] VoIPトークン: DBに登録済み → ✅ 両ユーザー確認済み

**サーバーログ確認**:
```
✅ APNs Provider initialized
📞 sendVoipPush: Sending to user 11
✅ sendVoipPush: Sent successfully
📞 sendVoipPush: Sending to user 10
✅ sendVoipPush: Sent successfully
```

→ **サーバー側は正常にVoIP Pushを送信している**

---

### 4. ✅ メッセージPush実装の確認（完了）

**確認項目**:
- [x] Signal Server: メッセージをオフラインユーザーに送信 → ✅ 実装済み
- [x] API Server: メッセージPush送信エンドポイント → ✅ 実装済み
- [x] push.js: APNs送信ロジック → ✅ 正しく実装

---

## 🔍 現在のシステム構成

### アプリ起動時（オンライン）

```
ユーザー11（発信） → Socket.IO → Signal Server → Socket.IO → ユーザー10（着信）
                                                              ↓
                                                        CallManager
                                                              ↓
                                                      ビデオ画面表示
```

**動作**: リアルタイムでSDP offer/answer/ICEをSocket.IO経由で交換

---

### アプリ停止時（オフライン）

```
ユーザー11（発信） → Socket.IO → Signal Server
                                    ↓ ユーザー10はオフライン検出
                                    ↓
                              ┌─────┴─────┐
                              ↓           ↓
                         API Server   API Server
                    (offer保存)    (VoIP Push送信)
                              ↓           ↓
                         Redis/DB      APNs
                                         ↓
                                   ユーザー10のデバイス
                                         ↓
                                   VoIP Push受信
                                         ↓
                                    CallKit表示
                                         ↓
                                   ユーザーが応答
                                         ↓
                                    アプリ起動
                                         ↓
                              APIからoffer取得
                                         ↓
                              WebRTC接続確立
                                         ↓
                              ビデオ画面表示
```

**動作**:
1. Signal Serverがオフライン検出
2. offerをAPIに保存
3. VoIP Pushを送信
4. ユーザーが応答
5. アプリがAPIからofferを取得
6. WebRTC接続確立

---

## 📋 テスト計画

### 事前準備

1. **アプリを再ビルド**（ポーリング機構を無効化したため）
   ```bash
   # Xcodeで
   Product → Clean Build Folder (Shift + Cmd + K)
   Product → Build (Cmd + B)
   Product → Run (Cmd + R)
   ```

2. **両デバイスでアプリを再起動**
   - アプリを完全終了
   - 再起動
   - ログイン確認

3. **Socket.IO接続を確認**
   ```
   期待されるログ:
   ✅ SocketService: Socket connected
   ✅ SocketService: Auto-registering user on connect
   ```

---

### テストケース 1: アプリ起動時の通話（Socket.IO）

**目的**: Socket.IOが正常に動作するか確認

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10に発信
3. ユーザー10で着信画面が表示されるか確認
4. 応答してビデオ通話ができるか確認

**期待される結果**:
- ✅ 着信画面が即座に表示される
- ✅ 応答後、ビデオ通話が確立される
- ✅ 双方向で音声・映像が届く

**確認するログ** (Xcode):
```
[User 11]
✅ SocketService: Socket connected
📞 CallManager: Initiating outgoing call
📤 SocketService: Sending offer to 10

[User 10]
✅ SocketService: Socket connected
📞 SocketService: Received offer from 11
📞 CallManager: Processing incoming call
```

**確認するログ** (Signal Server):
```bash
docker logs -f chutalk_signal

# 期待されるログ:
[signal] offer from 11 to 10
[signal] user 10 is online, sending via Socket.io
```

---

### テストケース 2: アプリ停止時の通話（VoIP Push）⚠️ 最重要

**目的**: VoIP Pushが正常に送信・受信されるか確認

**手順**:
1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. ユーザー11のアプリは起動したまま
3. **10秒待つ**（Socket.IOの切断を確実にするため）
4. ユーザー11がユーザー10に発信
5. ユーザー10のデバイスでCallKit着信画面が表示されるか確認
6. 応答してビデオ通話ができるか確認

**期待される結果**:
- ✅ ユーザー10のデバイスでCallKit着信画面が表示される（アプリ起動前）
- ✅ 応答すると自動的にアプリが起動する
- ✅ ビデオ通話画面が表示される
- ✅ 通話が確立される

**確認するログ** (Signal Server):
```bash
docker logs -f chutalk_signal

# 期待されるログ:
[signal] client connected: XXXXXXXX
[signal] user registered: 11 (socket=XXXXXXXX)
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
✅ [signal] Saved offer to API for callId: 11-10
📞 Sending VoIP Push to user 10
✅ VoIP Push sent to user 10
```

**確認するログ** (API Server):
```bash
docker logs -f chutalk_api

# 期待されるログ:
📞 API: Received offer for callId: 11-10
✅ API: Saved offer for callId: 11-10
📞 sendVoipPush: Sending to user 10
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
POST /api/internal/push/call 200 11 - XXX.XXX ms
```

**確認するログ** (ユーザー10のXcode - アプリが起動した後):
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: ...
📞 VoIPPushService: Reporting incoming call to CallKit
📞 CallKitProvider: reportIncomingCall
✅ VoIPPushService: CallKit report completed
📞 ContentView: ========== CALLKIT ANSWER ==========
📞 CallManager: Fetching offer from API for callId: 11-10
✅ CallManager: Offer retrieved from API
📞 CallManager: Creating peer connection
✅ CallManager: WebRTC connection established
```

---

### テストケース 3: バックグラウンド時の通話

**目的**: アプリがバックグラウンドにある時の動作確認

**手順**:
1. ユーザー10のアプリを起動した状態でホームボタンを押す（バックグラウンド化）
2. **画面をロック**
3. ユーザー11がユーザー10に発信
4. ユーザー10で着信が来るか確認

**期待される結果**:
- ケースA（Socket.IO接続中）: Socket.IO経由で着信
- ケースB（Socket.IO切断後）: VoIP Push経由で着信

**注意**: iOSはバックグラウンドでもSocket.IO接続を一定時間維持するため、すぐにVoIP Pushに切り替わらない場合があります。

---

### テストケース 4: メッセージ送信（アプリ起動時）

**目的**: Socket.IO経由のメッセージ送信確認

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10にメッセージを送信
3. ユーザー10でメッセージが届くか確認

**期待される結果**:
- ✅ メッセージが即座に表示される
- ✅ Socket.IO経由で送信される

---

### テストケース 5: メッセージ送信（アプリ停止時）⚠️ 重要

**目的**: メッセージPush通知が正常に送信・受信されるか確認

**手順**:
1. ユーザー10のアプリを完全に停止
2. 10秒待つ
3. ユーザー11がユーザー10にメッセージを送信
4. ユーザー10のデバイスで通知が表示されるか確認
5. 通知をタップしてメッセージが表示されるか確認

**期待される結果**:
- ✅ 通知バナーが表示される
- ✅ 通知音が鳴る
- ✅ 通知タップでアプリが起動し、メッセージが表示される

**確認するログ** (Signal Server):
```bash
docker logs -f chutalk_signal

# 期待されるログ:
[signal] user 10 is offline, sending message push
📨 Sending message Push to user 10
✅ Message Push sent to user 10
```

**確認するログ** (API Server):
```bash
docker logs -f chutalk_api

# 期待されるログ:
📤 sendMessagePush: Sending to user 10
📤 sendMessagePush: Sending to token 9f739db8afff2029...
✅ sendMessagePush: Sent successfully
```

---

## 🐛 トラブルシューティング

### VoIP Pushが届かない場合

**1. Signal Serverログを確認**
```bash
docker logs -f chutalk_signal
```

**期待されるログ**:
```
[signal] user 10 is offline, saving offer to API and sending VoIP Push
✅ [signal] Saved offer to API for callId: 11-10
📞 Sending VoIP Push to user 10
✅ VoIP Push sent to user 10
```

**ログが出ない場合**:
- Signal ServerがユーザーをまだOnlineと認識している可能性
- アプリ停止後、さらに待つ（20-30秒）
- Signal Serverを再起動: `docker restart chutalk_signal`

---

**2. API Serverログを確認**
```bash
docker logs -f chutalk_api
```

**期待されるログ**:
```
📞 sendVoipPush: Sending to user 10
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
```

**エラーが出る場合**:
- `⚠️ No VoIP tokens found` → VoIPトークンが登録されていない
  - 解決: アプリを再起動してVoIPトークンを再登録
- `❌ sendVoipPush: Failed` → APNs送信エラー
  - APNs証明書/環境変数を確認
  - APNs_ENV=sandbox が正しいか確認

---

**3. VoIPトークン登録を確認**
```bash
docker exec chutalk_db psql -U postgres -d chutalk -c \
  "SELECT user_id, LEFT(voip_token, 20) FROM devices WHERE user_id IN (10, 11);"
```

**期待される結果**:
```
 user_id |    voip_token
---------+----------------------
   11    | 27f7ca78a5062e650165
   10    | 9f739db8afff20298199
```

**トークンがない場合**:
- アプリを再起動
- ログインし直す
- Xcodeログで `✅ VoIPPushService: VoIP Token` が表示されるか確認

---

**4. APNs環境設定を確認**
```bash
docker exec chutalk_api printenv | grep APNS
```

**期待される出力**:
```
APNS_TEAM_ID=3KX7Q4LX88
APNS_KEY_ID=VLC43VS8N5
APNS_BUNDLE_ID=rcc.takaokanet.com.ChuTalk
APNS_ENV=sandbox
APNS_P8_PATH=/certs/AuthKey_VLC43VS8N5.p8
```

---

### Socket.IOが接続しない場合

**1. Xcodeログを確認**
```
期待されるログ:
✅ SocketService: Connecting to https://chutalk.ksc-sys.com
✅ SocketService: Connection initiated
✅ SocketService: Socket connected
🔵 SocketService: Auto-registering user on connect
```

**接続しない場合**:
- アプリを再起動
- ログインし直す
- Signal Serverを再起動: `docker restart chutalk_signal`

---

**2. Signal Serverログを確認**
```bash
docker logs -f chutalk_signal
```

**期待されるログ**:
```
[signal] client connected: XXXXXXXX
[signal] user registered: 10 (socket=XXXXXXXX)
```

---

### ビデオ通話が確立しない場合

**1. offer取得を確認**（VoIP Push経由の着信時）

**Xcodeログ**:
```
📞 CallManager: Fetching offer from API for callId: 11-10
✅ CallManager: Offer retrieved from API
```

**offerが取得できない場合**:
- Signal Serverがofferを保存していない可能性
- API Serverログで `/api/calls/signal/:callId POST` が成功しているか確認

---

**2. WebRTC接続を確認**

**Xcodeログ**:
```
📞 CallManager: Creating peer connection
📞 CallManager: Setting remote SDP
📞 CallManager: Creating answer
📞 CallManager: Sending answer
✅ CallManager: ICE connection state: connected
```

**接続失敗の場合**:
- STUN/TURNサーバーの設定を確認
- ネットワーク環境を確認（ファイアウォール、NAT等）

---

## 📊 期待される動作まとめ

| シナリオ | ユーザー10の状態 | 通信方法 | 期待される結果 |
|---------|----------------|---------|--------------|
| **通話** | アプリ起動中 | Socket.IO | ✅ 即座に着信画面表示 |
| **通話** | アプリ停止中 | VoIP Push | ✅ CallKit着信 → 応答 → ビデオ通話 |
| **通話** | バックグラウンド | Socket.IO or VoIP Push | ✅ 着信画面表示 |
| **メッセージ** | アプリ起動中 | Socket.IO | ✅ 即座にメッセージ表示 |
| **メッセージ** | アプリ停止中 | APNs Push | ✅ 通知バナー表示 |

---

## ✅ 次のステップ

1. **iOS アプリを再ビルド** ← 最初に実行
   - Product → Clean Build Folder
   - Product → Build
   - Product → Run

2. **両デバイスでアプリを再起動**

3. **テストケース1を実行**（アプリ起動時の通話）
   - 成功 → テストケース2へ
   - 失敗 → Socket.IO接続を確認

4. **テストケース2を実行**（アプリ停止時の通話）⚠️ 最重要
   - 成功 → テストケース5へ
   - 失敗 → サーバーログを確認

5. **テストケース5を実行**（メッセージPush）
   - 成功 → 全機能OK！
   - 失敗 → サーバーログを確認

6. **問題が発生した場合**
   - Xcodeログ、Signal Serverログ、API Serverログをすべて送ってください
   - どのテストケースで失敗したかを明記してください

---

**最終更新**: 2025年10月9日 16:30
**次回アクション**: アプリ再ビルド → テスト実行
