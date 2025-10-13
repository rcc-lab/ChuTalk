# VoIP Push受信問題の診断結果

**作成日時**: 2025年10月10日 00:20
**ステータス**: 🔍 診断完了 → 再ビルドとテストが必要

---

## 報告された問題

1. ❌ アプリを停止すると着信されない
2. ❌ ビデオ通話モードで着信できない

---

## コード分析の結果

### ✅ 正しく実装されているコンポーネント

#### 1. VoIPPushService.swift (Lines 76-178)

**実装状況**: ✅ 正しく実装済み

```swift
func pushRegistry(_ registry: PKPushRegistry,
                 didReceiveIncomingPushWith payload: PKPushPayload,
                 for type: PKPushType,
                 completion: @escaping () -> Void) {
    print("📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========")
    print("📞 VoIPPushService: Payload: \(payload.dictionaryPayload)")

    // ペイロード解析
    var voipPayload = VoIPPayload.parse(from: dict)

    // フォールバック処理（パース失敗時も必ずCallKitを呼ぶ）
    if voipPayload == nil {
        voipPayload = createFallbackPayload(from: dict)
    }

    // CallKitに報告
    CallKitProvider.shared.reportIncomingCall(
        uuid: uuid,
        handle: finalPayload.fromDisplayName,
        hasVideo: finalPayload.hasVideo,
        callId: finalPayload.callId,
        callerId: callerId
    ) {
        completion()
    }
}
```

**特徴**:
- ✅ PKPushRegistryDelegateを正しく実装
- ✅ ペイロード解析の寛容な処理（パース失敗時もフォールバック）
- ✅ CallKitへの正しい報告
- ✅ 二重処理防止（pendingCallIds）

#### 2. NotificationsService.swift (Lines 79-150)

**実装状況**: ✅ 正しく実装済み

```swift
func registerVoIPToken(_ token: String) {
    print("✅ NotificationsService: VoIP token: \(token)")

    Task {
        await uploadDeviceToken(apnsToken: apnsDeviceToken, voipToken: token)
    }
}

private func uploadDeviceToken(apnsToken: String?, voipToken: String?) async {
    // PUT /api/devices
    var body: [String: Any] = [
        "platform": "ios",
        "bundleId": Bundle.main.bundleIdentifier ?? "rcc.takaokanet.com.ChuTalk"
    ]
    if let voipToken = voipToken {
        body["voipDeviceToken"] = voipToken
    }
    // ... サーバーに送信
}
```

**特徴**:
- ✅ VoIPトークンをサーバーに正しく送信
- ✅ リトライ処理（最大3回、指数バックオフ）
- ✅ エラーハンドリング

#### 3. CallManager.swift (Line 482)

**実装状況**: ✅ 修正済み

```swift
// Detect video from SDP using accurate detection
let hasVideo = detectVideoFromSDP(sdp)
```

**修正内容**:
- ❌ 旧: `let hasVideo = sdp.contains("m=video")`
- ✅ 新: `let hasVideo = detectVideoFromSDP(sdp)`

#### 4. MessagingService.swift (Lines 109-111)

**実装状況**: ✅ 修正済み

```swift
// Also send via Socket.IO for real-time delivery and push notifications
SocketService.shared.sendMessage(to: userId, body: content)
print("✅ MessagingService: Sent message via Socket.IO to \(userId)")
```

---

## ログ分析

### 提供されたログの内容

#### サーバー側（API Server）

```
📞 sendVoipPush: Sending to user 11
   Type: call.incoming
   Call ID: 10-11
   From: rcc123 (10)
   Has Video: true
📞 sendVoipPush: Sending to token 27f7ca78a5062e65...
✅ sendVoipPush: Sent successfully
```

**分析**:
- ✅ VoIP Pushはサーバーから正常に送信されている
- ✅ APNsへの送信が成功している
- ℹ️ この例では、User 10がUser 11に発信している

#### iOS側（User 10アプリ起動時）

```
📞 VoIPPushService: ========== VOIP TOKEN UPDATED ==========
📞 VoIPPushService: VoIP Token: 9f739db8afff20298199ae3878c641b715e7b7f66e4bd16c456548812bada672
✅ SocketService: Socket connected
✅ NotificationsService: Device tokens uploaded successfully
```

**分析**:
- ✅ VoIPトークンが正常に取得されている
- ✅ サーバーへのアップロードが成功している
- ✅ Socket.IO接続も正常

### ❌ 重要な欠落

**VoIP Push受信時のログがない**:

以下のログが表示されるべきですが、提供されたログには含まれていません：
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: ...
📞 VoIPPushService: Reporting incoming call to CallKit
```

**これが意味すること**:
1. **最も可能性が高い**: アプリが停止している状態でVoIP Pushを受信するテストが実施されていない、または
2. VoIP Pushがデバイスに届いていない、または
3. アプリが古いバージョンで、ログ出力が異なる

---

## 根本原因の仮説

### 仮説1: アプリが再ビルドされていない（最も可能性が高い）⭐

**根拠**:
- CallManager.swiftとMessagingService.swiftの修正は完了している
- しかし、ユーザーは「ビデオ通話モードで着信できない」と報告している
- これは、修正されたコードがまだ実行されていないことを示唆している

**検証方法**:
1. Xcodeで Clean Build Folder (Shift + Cmd + K)
2. 再ビルド (Cmd + B)
3. デバイスにインストール (Cmd + R)
4. ログで以下を確認:
   ```
   🔍 CallManager: Video track detected in SDP (port: 9)
   ```
   または
   ```
   🔍 CallManager: No active video track in SDP
   ```

### 仮説2: VoIPトークンのミスマッチ

**根拠**:
- User 10のトークン: `9f739db8afff2029...`
- User 11に送信されたトークン: `27f7ca78a5062e65...`
- これらは異なるユーザーなので、トークンが異なるのは正常

**しかし**: User 10がアプリを停止して着信を受けるテストをした場合、サーバーがUser 10の正しいトークンを使用しているか確認が必要

**検証方法**:
サーバーログで以下を確認:
```bash
# User 10が着信を受ける場合のログ
docker logs -f chutalk_api 2>&1 | grep "sendVoipPush" -A 10
```

期待されるログ:
```
📞 sendVoipPush: Sending to user 10
📞 sendVoipPush: Sending to token 9f739db8afff2029...
```

トークンが一致しているか確認。

### 仮説3: APNs環境のミスマッチ

**根拠**:
- 開発環境（Xcode経由でインストール）のアプリは、Sandbox APNsを使用
- 本番環境（App Store経由）のアプリは、Production APNsを使用
- サーバーが間違った環境に送信している可能性

**検証方法**:
サーバー環境変数を確認:
```bash
ssh takaoka@192.168.200.50
docker exec chutalk_api env | grep APN
```

期待される設定:
```
APNS_ENVIRONMENT=sandbox  # 開発中の場合
APNS_KEY_ID=...
APNS_TEAM_ID=...
```

### 仮説4: Info.plistまたはEntitlementsの設定不足

**根拠**:
- VoIP Pushを受信するには、適切なバックグラウンドモードとCapabilityが必要

**確認すべき設定**:

1. **Info.plist**:
   ```xml
   <key>UIBackgroundModes</key>
   <array>
       <string>voip</string>
       <string>remote-notification</string>
   </array>
   ```

2. **Entitlements**:
   ```xml
   <key>aps-environment</key>
   <string>development</string>
   ```

---

## 解決手順

### ステップ1: アプリを再ビルド（必須）⭐

**重要**: すべての修正が適用されるように、必ずClean Build Folderから実施してください。

```
Xcode:
1. Product → Clean Build Folder (Shift + Cmd + K)
2. Product → Build (Cmd + B)
3. Product → Run (Cmd + R)
```

**確認するログ（ビルド後の初回起動）**:
```
📞 VoIPPushService: ========== VOIP TOKEN UPDATED ==========
📞 VoIPPushService: VoIP Token: [トークン]
✅ SocketService: Socket connected
✅ SocketService: Registered user: [ユーザーID]
✅ NotificationsService: Device tokens uploaded successfully
```

---

### ステップ2: ビデオ通話の着信テスト（アプリ起動中）

**目的**: detectVideoFromSDP()修正が適用されているか確認

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11からユーザー10に**ビデオ通話**で発信
3. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
```

**この修正が適用されている証拠**:
- `🔍 CallManager: Video track detected in SDP (port: 9)` が表示される
- 旧コードでは、このログは表示されない

**判定**:
- [ ] ✅ 上記のログが表示された → 修正が適用されています
- [ ] ❌ 上記のログが表示されない → 再ビルドが必要です

---

### ステップ3: 音声通話の着信テスト（アプリ起動中）

**目的**: 音声通話が正しく判定されるか確認

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11からユーザー10に**音声通話**で発信
3. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: No active video track in SDP
📞 CallManager: Reporting incoming call to CallKit
   Has Video: false
```

**判定**:
- [ ] ✅ `Has Video: false` と表示された → 正常
- [ ] ❌ `Has Video: true` と表示された → 修正が適用されていません

---

### ステップ4: VoIP Push着信テスト（アプリ停止時）⭐ 最重要

**目的**: アプリ停止時にVoIP Pushで着信できるか確認

**準備**:

ターミナル1（Signal Serverログ）:
```bash
ssh takaoka@192.168.200.50
docker logs -f chutalk_signal 2>&1 | grep --line-buffered -E "offer|offline|VoIP"
```

ターミナル2（API Serverログ）:
```bash
ssh takaoka@192.168.200.50
docker logs -f chutalk_api 2>&1 | grep --line-buffered "sendVoipPush" -A 10
```

**手順**:
1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. **1分間待つ**（Socket.IO接続が完全に切れるまで）
3. ユーザー11からユーザー10に**ビデオ通話**で発信
4. 両方のターミナルのログを確認
5. ユーザー10のデバイスで着信画面が表示されるか確認

**期待されるログ（Signal Server）**:
```
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
```

**期待されるログ（API Server）**:
```
📞 sendVoipPush: Sending to user 10
   Type: call.incoming
   Call ID: 11-10
   From: [ユーザー11の名前] (11)
   Has Video: true
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
```

**重要**: トークンが `9f739db8afff2029...` であることを確認してください（User 10のVoIPトークン）

**期待される動作（ユーザー10のデバイス）**:
- ✅ 画面が自動的にオンになる
- ✅ CallKit着信画面が表示される
- ✅ 「[ユーザー11の名前]からビデオ通話」と表示される

**もしXcodeが接続されている場合、以下のログも確認**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: {
    type = "call.incoming";
    callId = "11-10";
    fromUserId = 11;
    fromDisplayName = "...";
    hasVideo = 1;
}
📞 VoIPPushService: Reporting incoming call to CallKit
   UUID: ...
   Caller: ...
   Has Video: true
```

**判定**:
- [ ] ✅ 着信画面が表示された → VoIP Pushは正常に動作しています
- [ ] ❌ 着信画面が表示されなかった → 次のトラブルシューティングへ

---

## トラブルシューティング

### ケース1: ログで `🔍 CallManager: Video track detected` が表示されない

**原因**: 修正されたコードが実行されていない

**解決方法**:
1. Xcode: Product → Clean Build Folder (Shift + Cmd + K)
2. Xcode: Product → Build (Cmd + B)
3. デバイスを再起動
4. Xcode: Product → Run (Cmd + R)

---

### ケース2: VoIP Pushが送信されるが、着信画面が表示されない

**原因の可能性**:
1. トークンミスマッチ
2. APNs環境ミスマッチ
3. APNs証明書の問題
4. iOS設定の問題

**検証手順**:

#### A. トークンの一致を確認

**iOS側のトークン（アプリ起動時のログ）**:
```
📞 VoIPPushService: VoIP Token: 9f739db8afff20298199ae3878c641b715e7b7f66e4bd16c456548812bada672
```

**サーバー側のトークン（VoIP Push送信時のログ）**:
```
📞 sendVoipPush: Sending to token 9f739db8afff20298199ae3878c641b715e7b7f66e4bd16c456548812bada672
```

これらが**完全に一致**していることを確認してください。

**一致していない場合**:
1. アプリを起動して、トークンをサーバーに再登録
2. ログで `✅ NotificationsService: Device tokens uploaded successfully` を確認
3. 1分待つ（サーバーのキャッシュがクリアされるまで）
4. 再度テスト

#### B. APNs環境の確認

サーバーの環境変数を確認:
```bash
ssh takaoka@192.168.200.50
docker exec chutalk_api env | grep APNS_ENVIRONMENT
```

期待される値:
```
APNS_ENVIRONMENT=sandbox  # Xcode経由でインストールした場合
```

または
```
APNS_ENVIRONMENT=production  # App Store経由でインストールした場合
```

**ミスマッチの場合**:
- サーバーの `.env` ファイルを修正
- `docker-compose restart chutalk_api` で再起動

#### C. Entitlementsの確認

Xcodeで以下を確認:
1. プロジェクトを開く
2. Targets → ChuTalk → Signing & Capabilities
3. 「Push Notifications」Capabilityが追加されているか確認
4. 「Background Modes」で「Voice over IP」にチェックが入っているか確認

**不足している場合**:
1. 「+ Capability」をクリック
2. 「Push Notifications」を追加
3. 「Background Modes」を追加
4. 「Voice over IP」にチェック
5. 再ビルド

#### D. Info.plistの確認

`Info.plist` に以下が含まれているか確認:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>voip</string>
    <string>remote-notification</string>
</array>
```

**不足している場合**:
1. Info.plistを開く
2. 「Information Property List」を右クリック → Add Row
3. Key: `UIBackgroundModes`
4. Type: Array
5. Item 0: `voip`
6. Item 1: `remote-notification`
7. 再ビルド

---

### ケース3: サーバーログで「No VoIP tokens found」が表示される

**原因**: サーバーのデータベースにVoIPトークンが登録されていない

**解決方法**:

1. アプリを起動して、トークンをサーバーに送信
2. ログで以下を確認:
   ```
   ✅ NotificationsService: Device tokens uploaded successfully
   ```

3. サーバー側でデータベースを確認:
   ```bash
   ssh takaoka@192.168.200.50
   docker exec -it chutalk_postgres psql -U postgres -d chutalk
   ```

   SQL:
   ```sql
   SELECT id, user_id, voip_device_token
   FROM devices
   WHERE user_id = 10;
   ```

   期待される結果:
   ```
    id | user_id |                       voip_device_token
   ----+---------+----------------------------------------------------------------
     X |      10 | 9f739db8afff20298199ae3878c641b715e7b7f66e4bd16c456548812bada672
   ```

4. もしトークンがNULLの場合:
   - アプリを再起動
   - NotificationsServiceのログを確認
   - サーバーのAPIログでPUTリクエストを確認

---

## まとめ

### 現状

1. ✅ **コードの修正は完了している**
   - CallManager.swift: ビデオ/音声判定の修正済み
   - MessagingService.swift: Socket.IO送信の追加済み
   - VoIPPushService.swift: 正しく実装済み

2. ❓ **アプリの再ビルドが必要**
   - Clean Build Folderから再ビルドしていない可能性
   - 修正されたコードが実行されていない

3. ❓ **VoIP Push受信の検証が必要**
   - トークンの一致確認
   - APNs環境の確認
   - 実際の受信テスト

### 次のアクション

1. **必須**: アプリを再ビルド（Clean Build Folderから）
2. **テスト1**: ビデオ通話の着信（アプリ起動中）
3. **テスト2**: 音声通話の着信（アプリ起動中）
4. **テスト3**: VoIP Push着信（アプリ停止時）
5. **レポート**: 各テストの結果とログを報告

### 期待される効果

すべての修正が適用され、再ビルド後:

| テスト | 期待される結果 |
|--------|---------------|
| ビデオ通話（起動中） | ✅ ビデオ通話として着信する |
| 音声通話（起動中） | ✅ 音声通話として着信する |
| ビデオ通話（停止時） | ✅ VoIP Pushで着信する |
| 音声通話（停止時） | ✅ VoIP Pushで着信する |
| メッセージ（停止時） | ✅ Push通知が表示される |

---

**最終更新**: 2025年10月10日 00:20
**ステータス**: 🔍 診断完了 → 📦 再ビルドとテスト実施が必要
