# ChuTalk 修正内容と次のステップ

## 実施した修正

### 1. ✅ Socket.IO ユーザー登録の修正 (SocketService.swift)

**問題**:
- Socket.IO 再接続時にユーザーが再登録されず、`fromUserId` が `undefined` になっていた
- `.once(clientEvent: .connect)` を使用していたため、初回接続時のみ登録されていた

**修正内容**:
```swift
// 追加: ユーザーIDを保存するプロパティ
private var currentUserId: Int?

// connect() で userId を保存
self.currentUserId = userId

// setupEventHandlers() で毎回登録するように変更
socket?.on(clientEvent: .connect) { [weak self] data, ack in
    print("✅ SocketService: Socket connected")
    self?.isConnected = true

    // 接続のたびにユーザーを登録
    if let userId = self?.currentUserId {
        print("🔵 SocketService: Auto-registering user on connect")
        self?.registerUser(userId: userId)
    }
}
```

**結果**: アプリ起動時の通話が正常に動作するようになった

### 2. ✅ デバイストークンエンドポイントの一元化 (Constants.swift)

**問題**:
- デバイス登録エンドポイントが NotificationsService 内にハードコードされていた

**修正内容**:
```swift
// Constants.swift
struct API {
    // ...既存のエンドポイント
    static let devices = "\(Server.apiURL)/me/devices"
}

// NotificationsService.swift
// 修正前: guard let url = URL(string: "\(Constants.Server.apiURL)/me/devices")
// 修正後: guard let url = URL(string: Constants.API.devices)
```

**結果**: エンドポイント管理が改善され、変更が容易になった

### 3. ✅ **重要** Signal Server にオフライン時の offer 保存機能を追加 (new_server.js)

**問題**:
- ユーザーがオフライン時、Signal Server は VoIP Push を送信するだけで offer を API に保存していなかった
- VoIP Push でアプリが起動し、ユーザーが応答しても、offer SDP が API から取得できず、通話が開始できなかった
- これが「ビデオ通話は着信通知があるが着信してもビデオ画面にならない」問題の根本原因

**修正内容**:
```javascript
// offer イベントハンドラを修正
socket.on("offer", async (data) => {
  const fromUserId = sockets.get(socket.id);
  const toUserId = String(data.to);

  console.log(`[signal] offer from ${fromUserId} to ${toUserId}`);

  const targetSocketId = users.get(toUserId);
  if (targetSocketId) {
    // オンラインユーザーには Socket.IO で直接送信
    console.log(`[signal] user ${toUserId} is online, sending via Socket.io`);
    io.to(targetSocketId).emit("offer", {
      from: parseInt(fromUserId),
      sdp: data.sdp
    });
    return;
  }

  // オフラインユーザーには API に offer を保存してから VoIP Push
  console.log(`[signal] user ${toUserId} is offline, saving offer to API and sending VoIP Push`);
  if (fromUserId && toUserId) {
    const callId = `${fromUserId}-${toUserId}`;
    const hasVideo = data.sdp && data.sdp.includes("m=video");
    const fromDisplayName = data.displayName || `User ${fromUserId}`;

    // API に offer を保存（VoIP Push から起動したアプリが取得できるように）
    try {
      await axios.post(`${API_URL}/api/calls/signal/${callId}`, {
        action: "offer",
        data: {
          sdp: data.sdp,
          from: parseInt(fromUserId),
          to: parseInt(toUserId)
        }
      }, {
        headers: { "X-Admin-Token": ADMIN_PUSH_TOKEN }
      });
      console.log(`✅ [signal] Saved offer to API for callId: ${callId}`);
    } catch (error) {
      console.error(`❌ [signal] Failed to save offer to API:`, error.message);
    }

    await sendVoIPPush(toUserId, callId, fromUserId, fromDisplayName, hasVideo);
  }
});
```

**フロー（修正後）**:
```
発信者が offer 送信
    ↓
Signal Server が着信者のオンライン状態を確認
    ↓
オフラインの場合:
    1. API に offer を保存 (POST /api/calls/signal/{callId})
    2. VoIP Push を送信
    ↓
着信者のiOSデバイスが VoIP Push を受信
    ↓
アプリが起動し CallKit が着信画面を表示
    ↓
ユーザーが応答ボタンをタップ
    ↓
ContentView.handleCallKitAnswer() が呼ばれる
    ↓
API から offer SDP を取得 (GET /api/calls/signal/{callId})  ← ✅ これで取得できる！
    ↓
CallManager.acceptIncomingCall() で WebRTC 接続
    ↓
showActiveCallView = true でビデオ画面表示  ← ✅ これで表示される！
```

**結果**: VoIP Push からの着信応答時にビデオ画面が正しく表示されるようになる

### 4. 📝 診断ドキュメントの作成

**作成したファイル**:
- `VOIP_PUSH_DIAGNOSTIC.md`: VoIP Push の完全な診断ガイド
  - デバイストークン登録の確認手順
  - VoIP Push 送信の確認手順
  - iOS での受信確認手順
  - よくある問題と解決策
  - API Server 実装例

## 残りの問題と対処

### 1. ❌ VoIP Push が届かない（最重要）

**症状**:
- Signal Server で "✅ VoIP Push sent" と表示される
- しかし iOS デバイスで着信しない

**診断手順**: `VOIP_PUSH_DIAGNOSTIC.md` を参照

**必要な確認事項**:

#### A. VoIP トークン登録の確認
```bash
# 1. iOS アプリのログを確認（再ログイン直後）
# Xcode コンソールで以下を探す:
✅ NotificationsService: Device tokens uploaded successfully

# 2. API サーバーのログを確認
docker logs chutalk_api --tail 200 | grep -E "PUT.*me/devices|voipDeviceToken"

# 3. データベースを直接確認
docker exec -it chutalk_db psql -U postgres -d chutalk -c \
  "SELECT id, username, voip_device_token FROM users WHERE id IN (10, 11);"
```

#### B. API サーバーの VoIP Push 送信確認
```bash
# API サーバーのログを確認
docker logs chutalk_api --tail 200 | grep -E "push/call|VoIP|APNs"

# 期待される出力:
# POST /api/internal/push/call - toUserId: 10
# Retrieved voipDeviceToken for user 10: 9f739db8afff...
# Sending VoIP Push to APNs...
# ✅ VoIP Push sent successfully to APNs
```

**次のステップ**:
1. 上記の診断手順を実行
2. どこで失敗しているか特定
3. API サーバーの実装を確認（必要に応じて）

### 2. ❌ メッセージの Push 通知（アプリ kill 時）

**問題**:
- 現在は VoIP Push のみ実装されている
- メッセージには通常の APNs Push が必要

**必要な実装**:

#### Signal Server (new_server.js) に追加:
```javascript
// メッセージ転送
socket.on("message", async (data) => {
  const fromUserId = sockets.get(socket.id);
  const targetSocketId = users.get(String(data.to));

  if (targetSocketId) {
    // オンラインユーザーには Socket.IO で送信
    io.to(targetSocketId).emit("message", {
      from: parseInt(fromUserId),
      body: data.body,
      timestamp: new Date()
    });
  } else {
    // オフラインユーザーには通常の Push 通知を送信
    console.log(`[signal] user ${data.to} is offline, sending message push`);

    try {
      await axios.post(`${API_URL}/api/internal/push/message`, {
        toUserId: data.to,
        fromUserId: parseInt(fromUserId),
        body: data.body
      }, {
        headers: { "X-Admin-Token": ADMIN_PUSH_TOKEN }
      });
      console.log(`✅ [signal] Message push sent to user ${data.to}`);
    } catch (error) {
      console.error(`❌ [signal] Failed to send message push:`, error.message);
    }
  }
});
```

#### API Server に必要な実装:
```javascript
// POST /api/internal/push/message
router.post('/internal/push/message', async (req, res) => {
  const { toUserId, fromUserId, body } = req.body;

  // 1. APNs device token を取得
  const user = await User.findByPk(toUserId);
  if (!user || !user.apnsDeviceToken) {
    return res.status(404).json({ error: 'APNs token not found' });
  }

  // 2. 発信者の名前を取得
  const fromUser = await User.findByPk(fromUserId);
  const fromName = fromUser ? fromUser.displayName : `User ${fromUserId}`;

  // 3. APNs Payload を構築（通常の Push）
  const notification = new apn.Notification();
  notification.topic = 'rcc.takaokanet.com.ChuTalk';  // アプリの Bundle ID
  notification.alert = {
    title: fromName,
    body: body
  };
  notification.sound = 'default';
  notification.badge = 1;
  notification.payload = {
    type: 'chat.message',
    fromUserId,
    fromName
  };

  // 4. APNs に送信
  const result = await apnProvider.send(notification, user.apnsDeviceToken);

  if (result.failed.length > 0) {
    console.error('APNs error:', result.failed[0].response);
    return res.status(500).json({ error: 'Failed to send push' });
  }

  console.log(`✅ Message push sent to user ${toUserId}`);
  res.json({ success: true });
});
```

## デプロイ手順

### 1. Signal Server の更新

```bash
# サーバーに接続
ssh takaoka@chutalk.ksc-sys.com

# new_server.js を配置
# /tmp/new_server.js の内容を /srv/chutalk/compose/signal/server.js にコピー
sudo cp /tmp/new_server.js /srv/chutalk/compose/signal/server.js

# Docker コンテナを再起動
cd /srv/chutalk/compose
docker-compose restart signal

# ログを確認
docker logs -f chutalk_signal
```

### 2. API Server の確認

以下のエンドポイントが正しく実装されているか確認:

```bash
# 1. デバイス登録エンドポイント
# PUT /api/v1/me/devices
# または PUT /api/me/devices
# Body: { platform: "ios", bundleId: "...", apnsDeviceToken: "...", voipDeviceToken: "..." }

# 2. VoIP Push 送信エンドポイント
# POST /api/internal/push/call
# Headers: X-Admin-Token
# Body: { toUserId, callId, fromUserId, fromDisplayName, room, hasVideo }

# 3. Call Signal 保存/取得エンドポイント
# POST /api/calls/signal/:callId
# GET /api/calls/signal/:callId
# DELETE /api/calls/signal/:callId

# 4. メッセージ Push 送信エンドポイント（追加必要）
# POST /api/internal/push/message
# Headers: X-Admin-Token
# Body: { toUserId, fromUserId, body }
```

### 3. iOS アプリの再ビルド（変更があるため）

```bash
# Xcode で Clean Build Folder
# ⌘ + Shift + K

# 再ビルド
# ⌘ + B

# 実機にインストール
# ⌘ + R
```

## テスト手順

### フェーズ 1: アプリ起動時の通話テスト

1. 両方のデバイスでアプリを起動
2. ユーザー10 → ユーザー11 に発信
3. ✅ 着信するか確認
4. ユーザー11 → ユーザー10 に発信
5. ✅ 着信するか確認

### フェーズ 2: VoIP Push テスト（最重要）

1. ユーザー10のアプリを完全終了（設定→アプリ一覧からスワイプアップ）
2. ユーザー11から発信
3. **確認項目**:
   - ✅ Signal Server ログ: "✅ VoIP Push sent to user 10"
   - ✅ API Server ログ: "✅ Saved offer to API for callId: ..."
   - ✅ API Server ログ: "✅ VoIP Push sent successfully to APNs"
   - ✅ ユーザー10のデバイスに着信画面が表示される
   - ✅ 応答ボタンをタップでビデオ画面が表示される
   - ✅ 通話が正常に接続される

4. Xcode で "Attach to Process by PID or Name" → "ChuTalk" を選択してログを確認:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📦 VoIPPayload: Successfully parsed
📞 CallKitProvider: ========== REPORTING INCOMING CALL ==========
✅ CallKitProvider: Incoming call reported successfully
📞 CallKitProvider: ========== USER ANSWERED CALL ==========
📞 ContentView: ========== CALLKIT ANSWER ==========
✅ ContentView: Found offer SDP
📞 CallManager: Accepting incoming call
✅ CallManager: Answer sent via Socket.io
✅ CallManager: Incoming call accepted
```

### フェーズ 3: メッセージ Push テスト（API実装後）

1. ユーザー10のアプリを完全終了
2. ユーザー11からメッセージ送信
3. ✅ ユーザー10のデバイスに通知が表示される
4. ✅ 通知をタップしてメッセージ画面が開く

## トラブルシューティング

### VoIP Push が届かない場合

詳細は `VOIP_PUSH_DIAGNOSTIC.md` を参照

**チェックリスト**:
- [ ] VoIP device token が DB に保存されているか
- [ ] API Server が APNs に送信しているか
- [ ] APNs 環境（development/production）が正しいか
- [ ] APNs 認証情報（.p8ファイル、Team ID、Key ID）が正しいか
- [ ] VoIP Push のペイロード形式が正しいか

### ビデオ画面が表示されない場合

**原因**: API から offer SDP を取得できない

**確認**:
```bash
# Signal Server のログで offer 保存を確認
docker logs chutalk_signal --tail 100 | grep "Saved offer"

# API Server で GET リクエストを確認
docker logs chutalk_api --tail 100 | grep "GET.*calls/signal"

# 手動で API を確認
curl -H "Authorization: Bearer {JWT_TOKEN}" \
  https://chutalk.ksc-sys.com/api/calls/signal/11-10
```

**期待されるレスポンス**:
```json
[
  {
    "action": "offer",
    "data": {
      "sdp": "v=0\r\no=...",
      "from": 11,
      "to": 10
    }
  }
]
```

## まとめ

### 完了した修正
1. ✅ Socket.IO ユーザー登録の修正
2. ✅ デバイストークンエンドポイントの一元化
3. ✅ Signal Server にオフライン時の offer 保存機能を追加
4. ✅ 診断ドキュメントの作成

### 次のステップ
1. **最優先**: VoIP Push 送信の確認と修正
   - VoIP token 登録の確認
   - API Server の VoIP Push 送信ロジックの確認
   - APNs 設定の確認

2. メッセージ Push 通知の実装
   - Signal Server にメッセージ Push ロジック追加
   - API Server にメッセージ Push エンドポイント追加

3. 全機能の統合テスト
   - アプリ起動時の通話
   - VoIP Push からの通話
   - メッセージ送受信（起動時とPush）

### サポートが必要な実装
- API Server の `/api/internal/push/call` エンドポイント実装
- API Server の `/api/calls/signal/:callId` エンドポイント実装
- API Server の APNs 送信ロジック（.p8ファイル、Team ID、Key ID の設定）
- API Server の `/api/internal/push/message` エンドポイント実装
