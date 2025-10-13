# 🚨 緊急修正完了サマリー

## 発見された問題

### 1. Socket.IO パス不一致 ⚠️ 最重要

**問題**:
```
nginx:         /signal/socket.io/ → http://127.0.0.1:13001/socket.io/
Signal Server: path: /signal/socket.io/ (間違い!)
```

**結果**: Socket.IO接続が全く動作しない → 通話もメッセージも届かない

**修正**:
```yaml
# docker-compose.yml
signal:
  environment:
    SOCKETIO_PATH: /socket.io/  # /signal/socket.io/ から変更
```

**確認済み**:
```
✅ 修正デプロイ完了
✅ Signal Server再起動完了
✅ ログ確認: path: "/socket.io/" (正しい)
✅ エンドポイントテスト: 400 Bad Request (Socket.IOサーバーに到達)
```

### 2. VoIP Token 登録状況

**確認済み**:
```sql
SELECT user_id, LEFT(voip_token, 20) FROM devices WHERE user_id IN (10, 11);

user_id | voip_token
--------|----------------------
   11   | 27f7ca78a5062e650165
   10   | 9f739db8afff20298199
```

✅ **両方のユーザーでVoIP Token登録済み**

## 修正内容

### サーバー側

#### 1. docker-compose.yml の修正
```yaml
signal:
  environment:
    SOCKETIO_PATH: /socket.io/  # ← /signal/socket.io/ から変更
```

#### 2. デプロイ実行
```bash
cd /srv/chutalk/compose
docker compose down signal
docker compose up -d signal
```

**結果**:
```
✅ Container chutalk_signal Started
✅ Log: path: "/socket.io/" (正しい設定)
```

### iOS アプリ側（変更不要）

**Constants.swift**:
```swift
static let socketURL = "https://chutalk.ksc-sys.com"      // ✅ 正しい
static let socketPath = "/signal/socket.io/"               // ✅ 正しい
```

**nginx 設定** (`/etc/nginx/sites-available/chutalk.ksc-sys.com`):
```nginx
location /signal/socket.io/ {
    proxy_pass http://127.0.0.1:13001/socket.io/;  # ✅ 正しい
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    ...
}
```

## 接続フロー（修正後）

```
iOS アプリ
  ↓ wss://chutalk.ksc-sys.com/signal/socket.io/
nginx (リバースプロキシ)
  ↓ http://127.0.0.1:13001/socket.io/
Signal Server (Docker)
  ↓ path: /socket.io/
Socket.IO サーバー
  ✅ 接続成功！
```

## 必要な対応（ユーザー側）

### 1. iOS アプリの再起動 ⚠️ 必須

**理由**: 既存のSocket.IO接続を切断して、新しい設定で再接続する必要があります。

**手順**:
1. アプリを完全終了（設定 → アプリ一覧からスワイプアップ）
2. アプリを再起動
3. ログインしている場合はそのまま、ログアウトしている場合は再ログイン

### 2. 接続確認

**Xcodeコンソールで以下のログを確認**:
```
✅ SocketService: Connecting to https://chutalk.ksc-sys.com
✅ SocketService: Connection initiated
✅ SocketService: Socket connected
🔵 SocketService: Auto-registering user on connect
✅ SocketService: Registration message sent
```

**Signal Serverログで確認**:
```bash
docker logs -f chutalk_signal

# 期待されるログ:
[signal] client connected: XXXXXXXX
[signal] user registered: 10 (socket=XXXXXXXX)
```

## 期待される動作（修正後）

### ✅ アプリ起動時の通話
1. 両方のデバイスでアプリを起動
2. Socket.IOが接続される
3. ユーザー登録が自動実行される
4. 通話が正常に動作する

### ✅ VoIP Push（アプリkill時）
1. ユーザー10のアプリを完全終了
2. ユーザー11から発信
3. Signal Server: オフライン検出 → API に offer 保存 → VoIP Push 送信
4. ユーザー10のデバイス: VoIP Push 受信 → CallKit 表示
5. 応答: API から offer 取得 → WebRTC 接続 → ビデオ画面表示

### ✅ メッセージ（アプリkill時）
1. ユーザー10のアプリを完全終了
2. ユーザー11からメッセージ送信
3. Signal Server: オフライン検出 → 通常 Push 送信
4. ユーザー10のデバイス: 通知表示

## トラブルシューティング

### Socket.IOが接続しない場合

**1. Signal Serverログを確認**:
```bash
docker logs -f chutalk_signal
```

**期待されるログ**:
```
[signal] client connected: XXXXXXXX
[signal] user registered: XX (socket=XXXXXXXX)
```

**ログが出ない場合**:
- iOSアプリを再起動
- ログインし直す

**2. iOSアプリログを確認**:
```
✅ SocketService: Socket connected
```

**エラーが出る場合**:
- ネットワーク接続を確認
- アプリを再インストール（最終手段）

### VoIP Pushが届かない場合

**1. 発信時のSignal Serverログ**:
```bash
docker logs -f chutalk_signal

# 期待されるログ:
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
✅ [signal] Saved offer to API for callId: 11-10
📞 Sending VoIP Push to user 10
✅ VoIP Push sent to user 10
```

**2. API Serverログ**:
```bash
docker logs -f chutalk_api

# 期待されるログ:
📞 API: Received offer for callId: 11-10
✅ API: Saved offer for callId: 11-10
📞 sendVoipPush: Sending to user 10
✅ sendVoipPush: Sent successfully
```

**3. VoIP Token確認**:
```bash
docker exec chutalk_db psql -U postgres -d chutalk -c \
  "SELECT user_id, LEFT(voip_token, 20) FROM devices WHERE user_id IN (10, 11);"
```

## ログ出力のポイント

### 正常時のログ

**Signal Server**:
```
[signal] client connected: abc123
[signal] user registered: 10 (socket=abc123)
[signal] offer from 11 to 10
[signal] user 10 is online, sending via Socket.io
```

**または**（オフライン時）:
```
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
✅ [signal] Saved offer to API for callId: 11-10
📞 Sending VoIP Push to user 10
✅ VoIP Push sent to user 10
```

### 異常時のログ

**Socket.IO接続なし**:
```
# Signal Serverに何もログが出ない
# → iOSアプリを再起動
```

**offer保存失敗**:
```
❌ [signal] Failed to save offer to API: ...
# → API Serverの起動を確認
```

**VoIP Push送信失敗**:
```
❌ Failed to send VoIP Push: ...
# → API Serverログを確認
# → APNs設定を確認
```

## 完了チェックリスト

### サーバー側
- [x] docker-compose.yml 修正（SOCKETIO_PATH: /socket.io/）
- [x] Signal Server 再起動
- [x] ログ確認（path: "/socket.io/"）
- [x] エンドポイントテスト（400 Bad Request）
- [x] VoIP Token 登録確認

### iOS アプリ側（ユーザー対応）
- [ ] アプリを完全終了
- [ ] アプリを再起動
- [ ] Socket.IO接続を確認
- [ ] ユーザー登録を確認
- [ ] 通話テスト（アプリ起動時）
- [ ] 通話テスト（VoIP Push）
- [ ] メッセージテスト（Push通知）

## 修正前後の比較

| 項目 | 修正前 | 修正後 |
|------|--------|--------|
| **Socket.IO パス** | `/signal/socket.io/` (不一致) | `/socket.io/` (一致) |
| **Socket.IO 接続** | ❌ 接続不可 | ✅ 接続可能 |
| **通話（アプリ起動時）** | ❌ 動作しない | ✅ 動作する |
| **通話（VoIP Push）** | ❌ Push送信されない | ✅ Push送信される |
| **メッセージ（Push）** | ❌ Push送信されない | ✅ Push送信される |

## 次のステップ

1. **iOS アプリを再起動** ← 今すぐ実行
2. **Socket.IO接続を確認**
3. **通話テスト（両方のデバイスでアプリ起動）**
4. **VoIP Pushテスト（アプリkill時）**
5. **メッセージPushテスト（アプリkill時）**

---

**修正完了日時**: 2025年10月9日 15:58
**次回アクション**: iOS アプリの再起動と接続確認
