# VoIP Push + CallKit 実装ガイド

## 概要

ChuTalkアプリに、**アプリ未起動/バックグラウンドでも必ず鳴る**VoIP通話着信機能を実装しました。

### 実装の特徴

- **PushKit (VoIP Push)**: アプリが終了していても着信通知を受信
- **CallKit**: iOSシステム標準の着信UIと着信音
- **WebRTC**: 実際の音声/映像通話
- **既存機能の維持**: Socket.IO/WebRTCはそのまま使用

---

## アーキテクチャ

### 着信フロー

```
サーバー
  ↓ (VoIP Push送信)
APNs
  ↓
デバイス（アプリkill/バックグラウンドでも起動）
  ↓
VoIPPushService.didReceiveIncomingPush
  ↓
CallKitProvider.reportIncomingCall
  ↓
iOSシステム着信UI表示 + 着信音
  ↓
ユーザーが「応答」
  ↓
CallKitProvider.performAnswerCallAction
  ↓
ContentView.handleCallKitAnswer
  ↓
CallManager.acceptIncomingCall
  ↓
WebRTC接続確立
  ↓
通話開始
```

### 発信フロー

```
ユーザーが発信ボタンをタップ
  ↓
CallManager.startCall
  ↓
APIService.sendSignal (offer)
  ↓
サーバーがVoIP Pushを送信
  ↓
相手のデバイスで着信
```

---

## 実装ファイル

### 新規ファイル

| ファイル | 役割 |
|---------|------|
| **VoIPPayload.swift** | VoIP Pushペイロードのパーサー |
| **VoIPPushService.swift** | PushKit統合、トークン管理 |
| **CallKitProvider.swift** | CallKit統合、着信UI管理 |

### 更新ファイル

| ファイル | 変更内容 |
|---------|----------|
| **APIService.swift** | `registerVoIPDeviceToken` API追加 |
| **AppDelegate.swift** | VoIPPushService/CallKitProvider初期化 |
| **ContentView.swift** | `handleCallKitAnswer` を新形式に対応 |

---

## Xcodeプロジェクト設定

### 1. Capabilities設定

**Targets > Signing & Capabilities**

1. **Push Notifications** を追加
   - 「+ Capability」→「Push Notifications」

2. **Background Modes** を追加
   - 「+ Capability」→「Background Modes」
   - 以下にチェック:
     - ✅ Voice over IP
     - ✅ Remote notifications
     - ✅ Audio, AirPlay, and Picture in Picture

### 2. Info.plist設定

以下のキーを追加（既に設定済み）:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
    <string>fetch</string>
    <string>remote-notification</string>
</array>

<key>NSMicrophoneUsageDescription</key>
<string>音声通話およびビデオ通話を行うためにマイクへのアクセスが必要です</string>

<key>NSCameraUsageDescription</key>
<string>ビデオ通話を行うためにカメラへのアクセスが必要です</string>
```

### 3. Bundle IDとAPNs設定

- **Bundle ID**: `com.ksc-sys.rcc.ChuTalk`
- **VoIP APNs トピック**: `com.ksc-sys.rcc.ChuTalk.voip`

**APNs証明書の種類:**
- Development: Sandbox APNs (開発用)
- Production: Production APNs (リリース用)

---

## サーバー側API仕様

### 1. VoIPデバイストークン登録

```
PUT /api/me/devices
Headers: Authorization: Bearer <JWT>
Body:
{
  "voipDeviceToken": "<64文字の16進数文字列>",
  "bundleId": "com.ksc-sys.rcc.ChuTalk",
  "platform": "ios"
}

Response: 200 OK
```

### 2. VoIP Push送信（サーバー側実装）

サーバーは以下の条件でVoIP Pushを送信する必要があります:

**タイミング:**
- ユーザーAがユーザーBに発信したとき
- `/api/calls/signal` にofferが送信されたとき

**ペイロード:**
```json
{
  "aps": {
    "content-available": 1
  },
  "type": "call.incoming",
  "callId": "<UUID or unique call identifier>",
  "fromUserId": "11",
  "fromDisplayName": "テストユーザー",
  "room": "p2p:11-10"
}
```

**APNs送信先:**
- トピック: `com.ksc-sys.rcc.ChuTalk.voip`
- デバイストークン: `/api/me/devices` で登録されたトークン
- 環境: Sandbox (開発) / Production (本番)

---

## ビルドとテスト手順

### 前提条件

⚠️ **PushKitは実機でのみ動作します（シミュレータ不可）**

- iPhone実機
- 有効なApple Developer アカウント
- APNs証明書（開発用/本番用）

### 1. ビルド

```bash
# Xcodeでプロジェクトを開く
open ChuTalk.xcodeproj

# 実機を接続
# Product > Run (⌘R)
```

### 2. VoIPトークン確認

アプリを起動したら、Xcodeコンソールで以下のログを確認:

```
✅ AppDelegate: didFinishLaunchingWithOptions
✅ CallKitProvider: Initialized
📞 VoIPPushService: Registering for VoIP pushes...
✅ VoIPPushService: PushKit registered
📞 VoIPPushService: ========== VOIP TOKEN UPDATED ==========
📞 VoIPPushService: VoIP Token: 1a2b3c4d5e6f... (64文字)
📤 VoIPPushService: Uploading device token to server...
✅ VoIPPushService: Device token uploaded successfully
```

**トラブルシューティング:**

もし「Failed to upload device token」が表示される場合:
- サーバーが `/api/me/devices` エンドポイントを実装しているか確認
- JWT認証トークンが有効か確認

### 3. VoIP Push受信テスト

#### 方法1: サーバーから送信

サーバー側でVoIP Pushを送信:

```bash
# 例: Node.jsの apn パッケージを使用
const apn = require('apn');

const options = {
  token: {
    key: 'path/to/AuthKey_XXXXXXXXXX.p8',
    keyId: 'KEY_ID',
    teamId: 'TEAM_ID'
  },
  production: false  // Sandbox環境
};

const provider = new apn.Provider(options);

const notification = new apn.Notification({
  topic: 'com.ksc-sys.rcc.ChuTalk.voip',
  payload: {
    aps: { 'content-available': 1 },
    type: 'call.incoming',
    callId: 'test-call-123',
    fromUserId: '11',
    fromDisplayName: 'テストユーザー',
    room: 'p2p:11-10'
  },
  pushType: 'voip'
});

provider.send(notification, '<DEVICE_TOKEN>').then(result => {
  console.log('VoIP Push sent:', result);
});
```

#### 方法2: curl経由でAPNs送信

```bash
# JWT作成（省略）
# 以下のコマンドでAPNsにリクエスト

curl -v \
  --http2 \
  --header "apns-topic: com.ksc-sys.rcc.ChuTalk.voip" \
  --header "apns-push-type: voip" \
  --header "apns-priority: 10" \
  --header "authorization: bearer $JWT_TOKEN" \
  --data '{"aps":{"content-available":1},"type":"call.incoming","callId":"test-123","fromUserId":"11","fromDisplayName":"テストユーザー","room":"p2p:11-10"}' \
  https://api.sandbox.push.apple.com/3/device/<DEVICE_TOKEN>
```

### 4. 着信確認

VoIP Pushを送信すると、デバイスで以下が発生:

1. **アプリがkill状態でも起動**
2. **CallKitの着信画面が表示**
   - フルスクリーン着信UI
   - 「応答」「拒否」ボタン
   - 発信者名が表示
3. **着信音が鳴る**（システム標準）
4. **ロック画面でも表示**

**期待されるログ:**

```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: {...}
✅ VoIPPayload: Successfully parsed
   callId: test-call-123
   fromUserId: 11
   fromDisplayName: テストユーザー
📞 VoIPPushService: Reporting incoming call to CallKit
📞 CallKitProvider: ========== REPORTING INCOMING CALL ==========
   UUID: ...
   Handle: テストユーザー
   Call ID: test-call-123
   Caller ID: 11
✅ CallKitProvider: Incoming call reported successfully
✅ CallKitProvider: CallKit UI should be visible now
```

### 5. 応答テスト

着信画面で「応答」をタップ:

```
📞 CallKitProvider: ========== USER ANSWERED CALL ==========
   UUID: ...
   Call ID: test-call-123
   Caller ID: 11
✅ CallKitProvider: Audio session configured
📞 ContentView: ========== CALLKIT ANSWER ==========
   Call ID: test-call-123
   Caller ID: 11
📞 ContentView: Fetching offer signal from API...
✅ ContentView: Found offer signal
🔵 CallManager: Accepting incoming call from テストユーザー
```

WebRTC接続が確立され、通話が開始されます。

### 6. 拒否テスト

着信画面で「拒否」をタップ:

```
📞 CallKitProvider: ========== CALL ENDED ==========
   UUID: ...
   Call ID: test-call-123
📞 ContentView: CallKit end call
🔵 CallManager: Ending call
```

---

## トラブルシューティング

### 問題1: VoIPトークンが取得できない

**症状:**
```
📞 VoIPPushService: Registering for VoIP pushes...
✅ VoIPPushService: PushKit registered
(トークン更新のログが出ない)
```

**原因と対策:**
- シミュレータを使用している → **実機でテスト**
- Capabilitiesが設定されていない → Push NotificationsとBackground Modes (VoIP) を有効化
- Provisioning Profileが古い → Xcodeで再生成

### 問題2: VoIP Pushが届かない

**症状:**
サーバーからPushを送信しても、デバイスで着信しない

**原因と対策:**
1. **デバイストークンが正しいか確認**
   - Xcodeコンソールで表示された64文字のトークンを使用

2. **APNs環境を確認**
   - Development build → Sandbox APNs
   - App Store / TestFlight → Production APNs

3. **トピックを確認**
   - `com.ksc-sys.rcc.ChuTalk.voip` が正しいか

4. **ペイロード形式を確認**
   - `aps.content-available: 1` が必須
   - `pushType: 'voip'` を設定

5. **ネットワーク接続を確認**
   - Wi-Fiまたはモバイルデータが有効

### 問題3: 着信画面が表示されない

**症状:**
VoIP Pushは届くが、CallKitの着信画面が表示されない

**原因と対策:**

**ログでペイロードパース失敗を確認:**
```
❌ VoIPPayload: Missing required fields
```
→ ペイロードに `type`, `callId`, `fromUserId`, `fromDisplayName`, `room` が含まれているか確認

**CallKitのエラーを確認:**
```
❌ CallKitProvider: Failed to report incoming call
   Error code: 3
```
→ Info.plistに `NSMicrophoneUsageDescription` が設定されているか確認

### 問題4: 応答しても通話が開始されない

**症状:**
着信画面で「応答」をタップしても通話が開始されない

**原因と対策:**

**offerシグナルが見つからない:**
```
❌ ContentView: Failed to get signals
```
→ サーバーのシグナリングAPIを確認。`GET /api/calls/signal/{callId}` が正しく動作しているか

**WebRTC接続エラー:**
```
❌ CallManager: Failed to accept call
```
→ TURN資格が取得できているか、ネットワーク接続を確認

### 問題5: 着信音が鳴らない

**原因と対策:**

1. **デバイスが消音モード**
   - 物理的な消音スイッチを確認（iPhone側面）

2. **音量が0**
   - 音量ボタンで音量を上げる

3. **おやすみモード**
   - 設定 → 集中モード → すべてオフ

4. **CallKit設定**
   - システム標準の着信音が使用されます
   - カスタム着信音は `CXProviderConfiguration.ringtoneSound` で設定可能

---

## 現在の制限事項と今後の改善

### 現在の動作

✅ **アプリがフォアグラウンドの場合:**
- VoIP Pushで着信可能
- 既存のポーリングでも着信可能（NotificationService）

✅ **アプリがバックグラウンド/killの場合:**
- VoIP Pushで着信可能（この実装で対応）

### サーバー側で必要な実装

⚠️ **重要: サーバー側の対応が必要**

現在、クライアント側は完全に実装されていますが、以下のサーバー側実装が必要です:

1. **デバイストークン登録API**
   ```
   PUT /api/me/devices
   ```
   - voipDeviceTokenをデータベースに保存
   - ユーザーごとに複数デバイス対応

2. **VoIP Push送信ロジック**
   - `/api/calls/signal` でofferを受信したとき
   - 相手のvoipDeviceTokenを取得
   - APNsにVoIP Pushを送信

3. **シグナリングAPI**
   - `POST /api/calls/signal` - シグナル保存
   - `GET /api/calls/signal/{callId}` - シグナル取得

### 今後の改善案

1. **グループ通話対応**
   - 複数人での通話
   - CallKitのgrouping機能を使用

2. **通話履歴の充実**
   - 不在着信の記録
   - CallKitの通話履歴統合

3. **プッシュ通知のリトライ**
   - VoIP Push失敗時の自動リトライ
   - フォールバック通知

---

## デバッグのヒント

### ログレベル

すべての重要なイベントはログ出力されています:

- `✅` 成功
- `📞` CallKit/VoIP関連
- `📦` ペイロード処理
- `❌` エラー
- `⚠️` 警告

### ログ確認ポイント

**アプリ起動時:**
```
✅ AppDelegate: didFinishLaunchingWithOptions
✅ CallKitProvider: Initialized
📞 VoIPPushService: VoIP Token: ...
✅ VoIPPushService: Device token uploaded successfully
```

**VoIP Push受信時:**
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
✅ VoIPPayload: Successfully parsed
📞 CallKitProvider: ========== REPORTING INCOMING CALL ==========
✅ CallKitProvider: Incoming call reported successfully
```

**応答時:**
```
📞 CallKitProvider: ========== USER ANSWERED CALL ==========
📞 ContentView: ========== CALLKIT ANSWER ==========
🔵 CallManager: Accepting incoming call
```

---

## まとめ

この実装により、ChuTalkアプリは:

✅ **アプリ未起動/バックグラウンドでも着信が鳴る**
✅ **iOSシステム標準の着信UIを使用**
✅ **ロック画面でも着信表示**
✅ **既存のWebRTC通話機能と統合**
✅ **二重処理防止、エラーハンドリング、リトライロジック実装済み**

サーバー側でVoIP Push送信を実装すれば、完全に動作します。
