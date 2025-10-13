
# VoIP Push 実装ガイド (アプリ停止時の着信)

**作成日時**: 2025年10月10日

---

## 概要

このドキュメントは、ChuTalkアプリがバックグラウンド・完全停止状態でも着信を受け取れるようにするための実装ガイドです。

### 現在の状態

#### 動作している部分 ✅

1. **VoIPトークンの生成**: デバイスがVoIPトークンを正常に生成
   ```
   📞 VoIPPushService: VoIP Token: a8d6eb067dee41c3...
   ```

2. **トークンのサーバー送信**: サーバーにVoIPトークンが正常に保存される
   ```
   ✅ NotificationsService: Device tokens uploaded successfully
   ```

3. **サーバーからのVoIP Push送信**: サーバーがAPNsに正常に送信
   ```
   ✅ sendVoipPush: Sent successfully
   ```

4. **Bundle ID の一致**:
   - アプリ: `com.ksc-sys.rcc.ChuTalk`
   - サーバー: `com.ksc-sys.rcc.ChuTalk`
   - APNs証明書: Key ID `VLC43VS8N5`, Team ID `3KX7Q4LX88`

#### 動作していない部分 ❌

1. **デバイスのVoIP Push受信**: デバイスがVoIP Pushを受信していない
   ```
   # 期待されるログが表示されない:
   📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
   ```

---

## 問題の原因

### iOS 13以降のVoIP Push制限

iOS 13から、VoIP Pushに厳格な制限が導入されました:

> **VoIP Pushを受信したら、必ずCallKitを呼び出す必要がある**

もし呼び出さない場合:
- そのデバイスへのVoIP Push配信が**永久にブロック**される
- 開発中のテストで何度もVoIP Pushを受信してCallKitを呼ばなかった場合、ブロックされる

参考: https://developer.apple.com/documentation/pushkit/pkpushregistrydelegate/2875784-pushregistry

### 現在のデバイスの状態

User 10のデバイスは、過去の開発テスト中にVoIP Pushを受信してCallKitを呼び出さなかった可能性があり、APNsからブロックされている可能性があります。

---

## 解決方法

### 方法1: デバイスの完全リセット (推奨)

#### ステップ1: アプリを完全削除

1. ホーム画面でChuTalkアイコンを長押し
2. **「Appを削除」** をタップ
3. **「削除」** を確認

#### ステップ2: デバイスを再起動

1. 電源ボタン長押し → スライドで電源オフ
2. **30秒待つ**
3. 電源ボタン長押しで再起動

#### ステップ3: Xcodeでクリーンビルド

```bash
# Xcodeで以下を実行:
# Product → Clean Build Folder (Cmd + Shift + K)
# Product → Build (Cmd + B)
# Product → Run (Cmd + R)
```

#### ステップ4: 初期設定

1. アプリを起動
2. 通知許可をリクエストされたら**「許可」**
3. カメラ・マイク許可をリクエストされたら**「許可」**
4. User 10でログイン

**期待されるログ**:
```
✅ VoIPPushService: PushKit registered
📞 VoIPPushService: VOIP TOKEN UPDATED
📞 VoIPPushService: VoIP Token: [新しいトークン]
✅ NotificationsService: Device tokens uploaded successfully
```

#### ステップ5: 着信テスト

1. **User 10のアプリを完全に終了**（スワイプして閉じる）
2. **Xcodeのコンソールを接続したまま**（デバッグビルドの場合）
3. **User 11から発信**
4. **Xcodeコンソールを確認**

**期待されるログ**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: {...}
📞 VoIPPushService: Reporting incoming call to CallKit
✅ VoIPPushService: CallKit report completed
```

5. **User 10のデバイスで着信画面が表示されることを確認**

---

### 方法2: 別のデバイスでテスト

もし可能であれば、**別のデバイス**でテストしてください。

新しいデバイスであれば、VoIP Pushブロックの問題がないため、正常に動作するはずです。

---

### 方法3: デバイス設定の完全リセット (最終手段)

#### ⚠️ 警告: この方法はデバイスのすべてのデータを削除します

1. **設定 → 一般 → 転送またはiPhoneをリセット**
2. **「すべてのコンテンツと設定を消去」**
3. デバイスを初期化
4. 再度アプリをインストール

**注意**:
- バックアップを取ってから実施
- 個人データがすべて削除されます
- 最終手段としてのみ使用

---

## APNs接続の診断

### サーバー側の確認

#### 1. VoIP Push送信ログを確認

```bash
# サーバーにSSH接続
ssh takaoka@192.168.200.50

# APIサーバーのログを確認
docker logs -f chutalk_api | grep "voipPush"
```

**期待される出力**:
```
📞 sendVoipPush: Sending to user 10
📞 sendVoipPush: Sending to token a8d6eb067dee41c3...
✅ sendVoipPush: Sent successfully
```

**エラーの場合**:
```
❌ sendVoipPush: Failed: { reason: 'DeviceTokenNotForTopic' }
```
→ Bundle ID が不一致

```
❌ sendVoipPush: Failed: { reason: 'BadDeviceToken' }
```
→ トークンが無効 (デバイスリセットが必要)

#### 2. データベースのトークンを確認

```bash
# PostgreSQLに接続
docker exec -it chutalk_db psql -U postgres -d chutalk

# User 10のトークンを確認
SELECT user_id, LEFT(voip_device_token, 20), updated_at
FROM devices
WHERE user_id = 10;
```

**期待される出力**:
```
 user_id |         left         |         updated_at
---------+----------------------+----------------------------
      10 | a8d6eb067dee41c3... | 2025-10-10 14:30:00
```

### iOS側の確認

#### 1. VoIP Push受信の監視

Xcodeのコンソールで以下のログを監視:

```
# アプリ起動時
✅ VoIPPushService: PushKit registered

# VoIP Push受信時 (期待されるログ)
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
```

もし「INCOMING VOIP PUSH」が表示されない場合、デバイスがVoIP Pushを受信していません。

#### 2. 通知設定を確認

**設定 → ChuTalk → 通知**

- 通知を許可: **ON**
- サウンド: **ON**
- バッジ: **ON**
- バナー: **ON**

#### 3. ネットワーク接続を確認

VoIP Pushは**APNsサーバーとの常時接続**が必要です:

- Wi-Fi または モバイルデータ通信が有効
- 機内モードが無効
- VPNが干渉していない

---

## 開発中の注意事項

### VoIP Push ブロックを避けるための予防策

1. **VoIP Pushを受信したら、必ずCallKitを呼び出す**
   ```swift
   func pushRegistry(_ registry: PKPushRegistry,
                     didReceiveIncomingPushWith payload: PKPushPayload,
                     for type: PKPushType,
                     completion: @escaping () -> Void) {
       // ✅ 必ずCallKitを呼び出す
       CallKitProvider.shared.reportIncomingCall(...)
   }
   ```

2. **テスト時に何度もVoIP Pushを送信しない**
   - 1回のテストで確認
   - 頻繁にテストする必要がある場合は、複数のデバイスを用意

3. **コードを修正したら、必ずクリーンビルドして再インストール**
   ```bash
   # Product → Clean Build Folder
   # デバイスからアプリを削除
   # Product → Run
   ```

4. **本番環境とは別のAPNs証明書を使用**
   - 開発環境: `APNS_PRODUCTION=false`
   - 本番環境: `APNS_PRODUCTION=true`

---

## 実装の確認ポイント

### VoIPPushService.swift の確認

現在の実装は正しく、以下の処理を実行しています:

```swift
func pushRegistry(_ registry: PKPushRegistry,
                  didReceiveIncomingPushWith payload: PKPushPayload,
                  for type: PKPushType,
                  completion: @escaping () -> Void) {

    print("📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========")

    // 1. Payloadから情報を取得 ✅
    guard let callId = payloadDict["callId"] as? String,
          let callerId = payloadDict["callerId"] as? Int,
          let callerName = payloadDict["callerName"] as? String else {
        completion()
        return
    }

    // 2. CallKitに着信を報告 ✅ (iOS 13+ の必須要件)
    CallKitProvider.shared.reportIncomingCall(
        uuid: uuid,
        handle: callerName,
        hasVideo: hasVideo,
        callId: callId,
        callerId: callerId
    ) {
        print("✅ VoIPPushService: CallKit report completed")
        completion()  // ✅ 必ず completion を呼ぶ
    }
}
```

### CallKitProvider.swift の確認

CallKitProvider が正しくCXProviderを管理していることを確認:

```swift
func reportIncomingCall(uuid: UUID, handle: String, hasVideo: Bool,
                        callId: String, callerId: Int,
                        completion: @escaping () -> Void) {

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: handle)
    update.hasVideo = hasVideo
    update.localizedCallerName = handle

    // CXProviderに着信を報告
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
        if let error = error {
            print("❌ CallKitProvider: Failed to report incoming call - \(error)")
        } else {
            print("✅ CallKitProvider: Incoming call reported successfully")
        }
        completion()
    }
}
```

---

## トラブルシューティング

### Q1: デバイスリセット後もVoIP Pushが届かない

**考えられる原因**:
1. サーバーのAPNs証明書が間違っている
2. Bundle IDが不一致
3. ネットワーク接続の問題
4. APNsサーバーとの接続が確立されていない

**対処方法**:
1. サーバーログで「✅ sendVoipPush: Sent successfully」を確認
2. APNs証明書とBundle IDを再確認
3. 別のデバイスでテスト

### Q2: 通常のAPNs通知は届くのに、VoIP Pushだけ届かない

**原因**: VoIP Push配信がブロックされている

**対処方法**:
1. デバイスを完全リセット
2. 別のデバイスでテスト

### Q3: Xcodeコンソールに何も表示されない

**原因**: アプリが完全に終了しているため、コンソールログが表示されない

**対処方法**:
1. アプリを完全に終了
2. Xcodeで **Debug → Attach to Process by PID or Name...**
3. プロセス名に「ChuTalk」を入力
4. 着信を待つ
5. VoIP Pushでアプリが起動すると、コンソールに接続される

**または**:
- iPhone の **コンソール.app** (Macの場合)
- Xcodeの **Window → Devices and Simulators → View Device Logs**

---

## 次のステップ

### 短期的な対応

1. **User 10のデバイスをリセット** (方法1を実施)
2. **着信テストを実施**
3. **ログを確認して動作を検証**

### 中期的な対応

1. **複数デバイスでテスト環境を構築**
2. **テスト自動化スクリプトの作成**
3. **監視ダッシュボードの構築**

### 長期的な対応

1. **本番環境へのデプロイ**
2. **ユーザーフィードバックの収集**
3. **パフォーマンス最適化**

---

## 参考資料

- [Apple Developer - PushKit](https://developer.apple.com/documentation/pushkit)
- [Apple Developer - CallKit](https://developer.apple.com/documentation/callkit)
- [WWDC 2019 - Advances in App Background Execution](https://developer.apple.com/videos/play/wwdc2019/707/)

---

**最終更新**: 2025年10月10日
