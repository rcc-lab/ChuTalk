# VoIP Push 診断ガイド

## 現在の状況

### ✅ 動作している機能
- ユーザー10→11の通話（アプリ起動時）
- ユーザー11→10の通話（アプリ起動時）
- メッセージ送受信（アプリ起動時）
- Socket.IO接続とユーザー登録
- WebRTC シグナリング（offer/answer/ice）

### ❌ 動作していない機能
- **VoIP Push受信（アプリkill時）**
- メッセージ通知（アプリkill時）
- ビデオ通話の画面表示（着信後）

## VoIP Push の完全なフロー

### 1. デバイストークン登録フロー

```
iOS App起動
    ↓
VoIPPushService.registerForVoIPPushes()
    ↓
PushKit がトークンを生成
    ↓
didUpdate pushCredentials デリゲート呼び出し
    ↓
NotificationsService.registerVoIPToken()
    ↓
PUT /api/v1/me/devices
    {
        "platform": "ios",
        "bundleId": "rcc.takaokanet.com.ChuTalk",
        "voipDeviceToken": "9f739db8afff..."
    }
    Authorization: Bearer {JWT_TOKEN}
    ↓
APIサーバーがDBに保存
```

**重要**: このフローが成功しないと、VoIP Pushは届きません。

### 2. VoIP Push 送信フロー（アプリkill時）

```
発信者がoffer送信
    ↓
Signal Server (new_server.js)
    socket.on("offer") 受信
    ↓
users.get(toUserId) でSocket.IO接続確認
    ↓
接続なし（オフライン）
    ↓
POST /api/internal/push/call
    {
        "toUserId": 10,
        "callId": "11-10",
        "fromUserId": 11,
        "fromDisplayName": "User 11",
        "room": "p2p:11-10",
        "hasVideo": true
    }
    X-Admin-Token: {ADMIN_PUSH_TOKEN}
    ↓
APIサーバーが以下を実行:
    1. DBからtoUserIdのvoipDeviceTokenを取得
    2. Appleの APNs サーバーに VoIP Push 送信
    3. ペイロード形式:
       {
           "type": "call.incoming",
           "callId": "11-10",
           "fromUserId": 11,
           "fromDisplayName": "User 11",
           "room": "p2p:11-10",
           "hasVideo": true
       }
    ↓
Apple APNs サーバー
    ↓
デバイスに VoIP Push 配信
    ↓
iOS App (kill状態でも起動)
    VoIPPushService.didReceiveIncomingPushWith
    ↓
CallKitProvider.reportIncomingCall()
    ↓
iOSネイティブ着信画面表示
```

## 診断手順

### Step 1: VoIPトークン登録の確認

#### iOS アプリログをチェック（再ログイン直後）

```bash
# Xcodeコンソールで以下のログを確認:

✅ VoIPPushService: VoIP Token: 9f739db8afff...
✅ NotificationsService: VoIP token: 9f739db8afff...
✅ NotificationsService: Device tokens uploaded successfully  # ← これが出れば成功
```

もし以下のエラーが出る場合:
```
❌ NotificationsService: Upload failed with status 401
Response: {"error":"bad_token"}
```

**原因**: JWTトークンが無効または期限切れ
**対処**:
- アプリを完全削除して再インストール
- 再ログイン
- それでも401が出る場合、APIサーバーのJWT検証ロジックを確認

#### APIサーバーのログをチェック

```bash
# デバイス登録リクエストを確認
docker logs chutalk_api --tail 200 | grep -E "PUT.*me/devices|voipDeviceToken"

# 期待される出力例:
# PUT /api/v1/me/devices - 200 OK
# Saved voipDeviceToken for user 10: 9f739db8afff...
```

もしログが出ない場合:
- リクエストが届いていない（ネットワーク問題）
- エンドポイントが正しくない（`/api/v1/me/devices` を確認）

#### データベースを直接確認

```bash
# PostgreSQL の場合
docker exec -it chutalk_db psql -U postgres -d chutalk -c \
  "SELECT id, username, voip_device_token FROM users WHERE id IN (10, 11);"

# 期待される出力:
#  id | username | voip_device_token
# ----+----------+-------------------
#  10 | user10   | 9f739db8afff...
#  11 | user11   | 7e829ca7bef...
```

トークンが NULL の場合:
- デバイス登録が失敗している
- Step 1 の iOS ログとAPIログを再確認

### Step 2: VoIP Push 送信の確認

#### Signal Serverログ（ユーザー11がkill状態のユーザー10に発信した時）

```bash
docker logs chutalk_signal --tail 100

# 期待される出力:
# [signal] offer from 11 to 10
# [signal] user 10 is offline, sending VoIP Push
# 📞 Sending VoIP Push to user 10
# ✅ VoIP Push sent to user 10
```

もし以下のエラーが出る場合:
```
❌ Failed to send VoIP Push: Request failed with status code 401
```

**原因**: `ADMIN_PUSH_TOKEN` が不正
**対処**: `new_server.js` の `ADMIN_PUSH_TOKEN` 環境変数を確認

```
❌ Failed to send VoIP Push: connect ECONNREFUSED
```

**原因**: APIサーバーに接続できない
**対処**: `API_URL` 環境変数を確認（`http://api:3000` など）

#### APIサーバーログ（VoIP Push送信処理）

```bash
docker logs chutalk_api --tail 200 | grep -E "push/call|VoIP|APNs"

# 期待される出力:
# POST /api/internal/push/call - toUserId: 10
# Retrieved voipDeviceToken for user 10: 9f739db8afff...
# Sending VoIP Push to APNs...
# ✅ VoIP Push sent successfully to APNs
```

もし以下のエラーが出る場合:
```
❌ VoIP token not found for user 10
```

**原因**: Step 1のトークン登録が失敗
**対処**: Step 1に戻る

```
❌ APNs error: BadDeviceToken
```

**原因**:
- development環境のトークンをproduction APNsサーバーに送信
- またはその逆
**対処**: APNs環境設定を確認（development vs production）

```
❌ APNs error: InvalidProviderToken
```

**原因**: APNs認証トークン（JWT）が不正
**対処**:
- APNs Auth Key (.p8ファイル) を確認
- Team ID, Key ID が正しいか確認

### Step 3: iOS アプリでのVoIP Push受信確認

#### アプリを完全killした状態でテスト

1. iOS設定 → アプリ一覧 → ChuTalkをスワイプアップして完全終了
2. もう1台のデバイスから発信
3. Xcodeで"Attach to Process by PID or Name"で ChuTalk を選択
4. 着信後にログを確認

```
# 期待されるログ:
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: {
    "type": "call.incoming",
    "callId": "11-10",
    "fromUserId": 11,
    "fromDisplayName": "User 11",
    "room": "p2p:11-10",
    "hasVideo": true
}
📦 VoIPPayload: Parsing payload...
✅ VoIPPayload: Successfully parsed
📞 VoIPPushService: Reporting incoming call to CallKit
✅ VoIPPushService: CallKit report completed
```

もしログが全く出ない場合:
- VoIP Pushが届いていない
- Step 2のAPIサーバーログを確認
- Apple Developer Consoleでプッシュ証明書を確認

## チェックリスト

### iOS 設定
- [x] Info.plist に `UIBackgroundModes` で `voip` を有効化
- [x] Entitlements に `aps-environment` 設定（development/production）
- [x] VoIPPushService が PushKit を登録
- [x] VoIPPayload パース処理が正しい

### Signal Server (new_server.js)
- [x] オンライン/オフライン判定ロジック
- [x] VoIP Push 送信処理（`sendVoIPPush` 関数）
- [x] 環境変数: `API_URL`, `ADMIN_PUSH_TOKEN`, `SOCKETIO_PATH`
- [ ] **確認が必要**: 実際にVoIP Push APIが呼ばれているか

### API Server
- [ ] **確認が必要**: `PUT /api/v1/me/devices` エンドポイント実装
- [ ] **確認が必要**: `POST /api/internal/push/call` エンドポイント実装
- [ ] **確認が必要**: VoIP device token のDB保存
- [ ] **確認が必要**: APNs への VoIP Push 送信処理
- [ ] **確認が必要**: APNs 認証情報（.p8ファイル、Team ID、Key ID）

## よくある問題と解決策

### 問題1: 401 Unauthorized エラー（トークン登録時）

**症状**:
```
❌ NotificationsService: Upload failed with status 401
```

**原因**:
- JWTトークンの期限切れ
- Authorization ヘッダーの形式が不正
- APIサーバー側のJWT検証ロジックのバグ

**解決策**:
1. アプリを完全削除して再インストール
2. 再ログイン
3. KeychainManagerのトークン保存を確認
4. APIサーバーのJWT検証ロジックをデバッグ

### 問題2: VoIP Push が届かない（アプリkill時）

**症状**:
- Signal Serverで "✅ VoIP Push sent" と出る
- しかしiOSデバイスで着信しない

**原因パターン A**: VoIP token が登録されていない
```bash
# DBを確認
docker exec -it chutalk_db psql -U postgres -d chutalk -c \
  "SELECT id, voip_device_token FROM users WHERE id = 10;"
```
→ NULLなら Step 1 に戻る

**原因パターン B**: APIサーバーがAPNsに送信していない
```bash
# APIログを確認
docker logs chutalk_api --tail 200 | grep -i "apns"
```
→ ログが出ないならAPIサーバーの実装を確認

**原因パターン C**: APNs 環境の不一致
- development証明書なのにproduction APNsサーバーに送信
- または逆

**解決策**:
```javascript
// APIサーバーで APNs 環境を確認
const apnProvider = new apn.Provider({
  token: {
    key: fs.readFileSync('./AuthKey_XXXXXX.p8'),
    keyId: 'YOUR_KEY_ID',
    teamId: 'YOUR_TEAM_ID'
  },
  production: false  // ← development環境ならfalse
});
```

### 問題3: ペイロード形式の不一致

**症状**:
```
⚠️ VoIPPushService: Parse failed, creating fallback payload
```

**原因**: APIサーバーが送信するペイロードが期待される形式と異なる

**正しいペイロード形式**:
```json
{
  "type": "call.incoming",
  "callId": "11-10",
  "fromUserId": 11,
  "fromDisplayName": "User 11",
  "room": "p2p:11-10",
  "hasVideo": true
}
```

**注意点**:
- `fromUserId` は Int または String（パース時に変換される）
- `hasVideo` は Bool または String("true"/"false")
- `type` は省略可能（デフォルト: "call.incoming"）
- `callId` は必須

## 次のステップ

1. **まず Step 1 を実行**: VoIP token 登録を確認
   - iOSログで "✅ Device tokens uploaded successfully" を確認
   - DBでトークンが保存されていることを確認

2. **次に Step 2 を実行**: VoIP Push 送信を確認
   - Signal Serverログで送信を確認
   - APIサーバーログでAPNs送信を確認

3. **最後に Step 3 を実行**: iOS での受信を確認
   - アプリをkillして発信テスト
   - Xcodeでログを確認

4. **それでも解決しない場合**:
   - APIサーバーの `/api/internal/push/call` エンドポイントの実装を確認
   - APNs 認証情報（.p8ファイル、Team ID、Key ID）を確認
   - Apple Developer Console でプッシュ証明書を確認

## 参考: API Server 実装例

VoIP Push を送信する API エンドポイントの実装例:

```javascript
// POST /api/internal/push/call
router.post('/internal/push/call', async (req, res) => {
  const { toUserId, callId, fromUserId, fromDisplayName, room, hasVideo } = req.body;

  // 1. VoIP device token を取得
  const user = await User.findByPk(toUserId);
  if (!user || !user.voipDeviceToken) {
    console.error(`VoIP token not found for user ${toUserId}`);
    return res.status(404).json({ error: 'VoIP token not found' });
  }

  // 2. APNs Payload を構築
  const notification = new apn.Notification();
  notification.topic = 'rcc.takaokanet.com.ChuTalk.voip';  // VoIP bundle ID
  notification.pushType = 'voip';
  notification.payload = {
    type: 'call.incoming',
    callId,
    fromUserId,
    fromDisplayName,
    room,
    hasVideo
  };

  // 3. APNs に送信
  const result = await apnProvider.send(notification, user.voipDeviceToken);

  if (result.failed.length > 0) {
    console.error('APNs error:', result.failed[0].response);
    return res.status(500).json({ error: 'Failed to send VoIP push' });
  }

  console.log(`✅ VoIP Push sent to user ${toUserId}`);
  res.json({ success: true });
});
```
