# VoIP Push通知 修正履歴

## 📅 作業日時
2025-10-11

## 🎯 目的
ChuTalkアプリで、アプリが完全終了状態でもVoIP Push通知による着信を受信できるようにする

---

## ❌ 発生していた問題

### 症状
1. **バックグラウンド状態**: VoIP Pushを受信するが、アプリがクラッシュ
2. **アプリ完全終了状態**: VoIP Pushが受信されない

### エラーメッセージ
```
Apps receving VoIP pushes must post an incoming call via CallKit in the same run loop
Killing app because it never posted an incoming call to the system after receiving a PushKit VoIP push
```

---

## 🔍 根本原因

### iOS 13+の要件違反
**VoIP Push受信時、CallKitへの着信報告を同じrun loopで実行する必要がある**

### 問題のコード (VoIPPushService.swift:177)
```swift
// ❌ 誤り: 次のrun loopに遅延
DispatchQueue.main.async { [weak self] in
    CallKitProvider.shared.reportIncomingCall(
        uuid: uuid,
        handle: finalPayload.fromDisplayName,
        hasVideo: finalPayload.hasVideo,
        callId: finalPayload.callId,
        callerId: callerId
    ) {
        print("✅ VoIPPushService: CallKit report completed")
        self?.pendingCallIds.remove(finalPayload.callId)
        completion()
    }
}
```

**問題点:**
- `DispatchQueue.main.async`により、CallKit呼び出しが次のrun loopに遅延
- iOS 13+では、同じrun loop内でCallKitを呼ぶ必要がある
- 遅延するとiOSがアプリを強制終了

---

## ✅ 解決策

### 1. CallKitの同期呼び出し

**修正後のコード (VoIPPushService.swift:177)**
```swift
// ✅ 修正: 同じrun loopで即座に実行
// iOS 13+ requires immediate CallKit report in same run loop
CallKitProvider.shared.reportIncomingCall(
    uuid: uuid,
    handle: finalPayload.fromDisplayName,
    hasVideo: finalPayload.hasVideo,
    callId: finalPayload.callId,
    callerId: callerId
) { [weak self] in
    print("✅ VoIPPushService: CallKit report completed")
    self?.pendingCallIds.remove(finalPayload.callId)
    completion()
}
```

**変更点:**
- `DispatchQueue.main.async`ラッパーを削除
- CallKitを直接、同期的に呼び出し

### 2. Bundle IDの変更

**理由:**
- 過去のVoIP Push違反により、旧Bundle IDがブロックされていた可能性
- iOS 13+のVoIP Push要件違反によるデバイス×Bundle ID単位のブロック

**変更:**
- `com.ksc-sys.rcc.ChuTalk` → `com.ksc-sys.rcc.ChuTalk3`

### 3. iOS 15互換性対応

**問題:**
- `.gradient` APIはiOS 16.0+のみ対応
- 中部特機のiPhone (iOS 15.8.4) でビルドエラー

**修正ファイル:**
1. `IncomingCallScreen.swift:93`
2. `ContentView.swift:79`

```swift
// 修正前
.background(Color.blue.gradient)

// 修正後
.background(Color.blue)
```

**Podfile変更:**
```ruby
# 修正前
platform :ios, '16.0'

# 修正後
platform :ios, '15.0'
```

### 4. 廃止されたentitlementの削除

**削除したentitlement:**
```xml
<key>com.apple.developer.pushkit.unrestricted-voip</key>
<true/>
```

**理由:**
- iOS 13+では不要（廃止された）
- 含めるとProvisioning Profile生成に失敗

**最終的なChuTalk.entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>
```

---

## 📋 最終設定

### iOS側設定

| 項目 | 設定値 |
|------|--------|
| Bundle ID | `com.ksc-sys.rcc.ChuTalk3` |
| VoIP Topic | `com.ksc-sys.rcc.ChuTalk3.voip` |
| iOS最小バージョン | 15.0 |
| Deployment Target | iOS 15.0 |

### Info.plist (UIBackgroundModes)
```xml
<key>UIBackgroundModes</key>
<array>
	<string>audio</string>
	<string>voip</string>
	<string>fetch</string>
	<string>remote-notification</string>
</array>
```

### サーバー側設定 (/srv/chutalk/compose/.env)
```bash
APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk3
APNS_ENV=sandbox
APNS_TEAM_ID=3KX7Q4LX88
APNS_KEY_ID=VLC43VS8N5
APNS_P8_PATH=/certs/AuthKey_VLC43VS8N5.p8
```

---

## 🧪 テスト結果

### テスト環境
- デバイス: 中部特機のiPhone (iOS 15.8.4)
- ユーザーID: 10
- VoIPトークン: `5b1bbd097d6b8ed7cf17d53d83bcb3e86f54bedb954e67e4ab818ff876bde4cd`

### テスト1: バックグラウンド状態
- **手順**: アプリをホームボタンでバックグラウンドに送る
- **結果**: ✅ 成功 - CallKit着信画面が表示
- **APNs Status**: 200
- **APNs ID**: `C598EAAB-47B3-3F9A-74C7-EB651FD20BF0`

### テスト2: アプリ完全終了状態
- **手順**: マルチタスク画面からアプリを上にスワイプして完全終了
- **結果**: ✅ 成功 - CallKit着信画面が表示
- **APNs Status**: 200
- **APNs ID**: `268466B4-CB7B-75E0-C7A8-33D77FC5561C`

### テスト用コマンド (サーバー側)
```bash
cd /srv/chutalk/compose
docker compose exec -T api node /app/test-voip-quick.js
```

---

## 📝 修正ファイル一覧

### iOS側
1. **VoIPPushService.swift** (Line 177)
   - CallKitの同期呼び出しに修正

2. **IncomingCallScreen.swift** (Line 93)
   - `.gradient` → `Color.blue`

3. **ContentView.swift** (Line 79)
   - `.gradient` → `Color.blue`

4. **ChuTalk.entitlements**
   - 廃止されたpushkit entitlementを削除

5. **project.pbxproj**
   - Bundle ID変更: `com.ksc-sys.rcc.ChuTalk3`

6. **Podfile**
   - `platform :ios, '15.0'`

### サーバー側
1. **/srv/chutalk/compose/.env**
   - `APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk3`

2. **/app/test-voip-quick.js** (新規作成)
   - VoIP Pushテスト用スクリプト

---

## 🎓 学んだこと

### iOS 13+ VoIP Push要件
1. **同じrun loopでCallKitを呼ぶ**: `DispatchQueue.main.async`は使わない
2. **必ずCallKitを呼ぶ**: VoIP Pushを受信したら必ず`reportIncomingCall`を呼ぶ
3. **違反するとブロック**: デバイス×Bundle ID単位でVoIP Push配信が停止される

### デバッグ手法
1. **アプリの完全削除と再インストール**: 設定をクリーンな状態にリセット
2. **Bundle ID変更**: 過去の違反履歴からの回復
3. **Xcodeコンソールでのログ確認**: VoIP Push受信の詳細を追跡

### Docker環境変数の更新
- `docker compose restart`では環境変数は再読み込みされない
- `docker compose down && docker compose up -d`が必要

---

## 🚀 次のステップ

### 短期
1. ✅ ~~VoIP Pushの動作確認~~ (完了)
2. 実際のユーザー間通話フローをテスト
   - 着信 → 応答 → 通話 → 終了
3. 複数デバイスでのテスト

### 中期
1. 本番環境への移行
   - Production APNs証明書の準備
   - `.env`の`APNS_ENV=production`設定
2. App Storeへの提出準備
   - Bundle ID: `com.ksc-sys.rcc.ChuTalk3`での本番証明書取得

### 長期
1. 通話品質の監視
2. エラーログの収集と分析
3. ユーザーフィードバックの収集

---

## 📚 参考リンク

- [Apple - PushKit Documentation](https://developer.apple.com/documentation/pushkit)
- [Apple - CallKit Documentation](https://developer.apple.com/documentation/callkit)
- [iOS 13+ VoIP Push Best Practices](https://developer.apple.com/documentation/pushkit/responding_to_voip_notifications_from_pushkit)

---

## ✍️ 作業者メモ

**重要:**
- VoIP Pushの違反は**デバイス×Bundle ID単位**でブロックされる
- アカウント（Team）単位のブロックは実務上ほぼない
- CallKitは必ず同じrun loopで呼ぶこと（`DispatchQueue.main.async`禁止）

**トラブルシューティング:**
- VoIP Pushが届かない場合は、アプリの完全削除→再インストールを試す
- サーバーログでAPNs Statusが200でも、iOS側で受信されない場合はデバイス×Bundle IDブロックの可能性
- その場合はBundle IDを変更して新しい状態でテスト

---

**作成日:** 2025-10-11
**最終更新:** 2025-10-11
**ステータス:** ✅ VoIP Push完全動作確認済み
