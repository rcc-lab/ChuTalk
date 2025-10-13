# 着信デバッグガイド

## 問題: 通話着信が鳴らない

このガイドを使用して、着信が鳴らない原因を特定してください。

---

## Step 1: アプリ起動時のログ確認

アプリを起動したときに、以下のログが表示されることを確認してください。

### 期待されるログ
```
✅ CallKitService: Initialized
👤 ContentView: 現在のユーザーID: 10
🔍 ContentView: 着信監視を開始します
✅ NotificationService: Starting monitoring for user 10
✅ NotificationService: メッセージと着信のポーリングを開始します
✅ NotificationService: タイマー設定完了 - メッセージ: 2秒, 着信: 1秒
🔍 NotificationService: 着信チェック開始 - User ID: 10
```

### チェックポイント
- ✅ CallKitServiceが初期化されている
- ✅ NotificationServiceのタイマーが設定されている
- ✅ 着信チェックが開始されている

**もしこれらのログが表示されない場合:**
- ContentView.swift の `startServices()` が呼ばれていない
- AuthServiceで認証されていない（ログインしていない）

---

## Step 2: 定期的なポーリングの確認

1秒ごとに以下のログが表示されることを確認してください。

### 期待されるログ
```
🔍 NotificationService: 着信チェック開始 - User ID: 10
🔍 NotificationService: 着信チェック完了 - checked: X, found signals: 0
```

### チェックポイント
- ✅ 1秒ごとにチェックが実行されている
- ✅ checked数が増えている（APIリクエストが成功している）

**もしログが表示されない場合:**
- Timerが動作していない
- Taskがキャンセルされている

**もし "No auth token" エラーが出る場合:**
```
❌ NotificationService: No auth token
```
- 認証トークンが取得できていない
- 再ログインが必要

---

## Step 3: 着信時のログ確認

相手から発信したときに、以下のログが表示されることを確認してください。

### 着信検出時
```
🔍 NotificationService: Signals found for callId 11-10: 1 signals
🔍 NotificationService: Signal data: [...]
🔍 NotificationService: Signal action: offer
📞 NotificationService: 着信検出！ CallID: 11-10
📞 NotificationService: 発信者: 11 → 着信者: 10
📞 NotificationService: SDP length: 2345
📞 NotificationService: Caller name: rcc122
📞 NotificationService: Calling CallKitService.reportIncomingCall
```

### CallKit表示時
```
📞 CallKitService: ========== INCOMING CALL ==========
📞 CallKitService: UUID: ...
📞 CallKitService: Handle: rcc122
📞 CallKitService: Has Video: false
📞 CallKitService: Caller ID: 11
📞 CallKitService: Calling provider.reportNewIncomingCall...
✅ CallKitService: Incoming call reported successfully
✅ CallKitService: CallKit UI should be visible now
✅ NotificationService: CallKit completion handler called
```

---

## 問題パターン別の対処法

### パターン 1: ポーリングが動いていない

**症状:**
```
🔍 NotificationService: 着信チェック開始 - User ID: 10
```
このログが1秒ごとに表示されない

**原因:**
- Timerが正しく設定されていない
- ContentViewのstartServices()が呼ばれていない

**対処法:**
1. アプリを再起動
2. ログアウト→ログイン
3. Xcodeでビルドし直す

---

### パターン 2: Signalが取得できていない

**症状:**
```
🔍 NotificationService: 着信チェック完了 - checked: 0, found signals: 0
```
checked が 0 のまま

**原因:**
- API認証エラー
- ネットワークエラー

**対処法:**
1. 認証トークンを確認:
```
❌ NotificationService: No auth token
```
が出ていないか確認

2. ネットワーク接続を確認

3. APIエンドポイントを確認:
```
https://chutalk.ksc-sys.com/api/calls/signal/{callId}
```

---

### パターン 3: Offerが検出されない

**症状:**
```
🔍 NotificationService: Signals found for callId 11-10: 1 signals
🔍 NotificationService: Signal data: [...]
```
Signalはあるが、offerが見つからない

**原因:**
- Signalの形式が正しくない
- actionフィールドが "offer" でない

**対処法:**
1. Signal dataログでJSONを確認
2. 以下の形式になっているか確認:
```json
[
  {
    "action": "offer",
    "data": {
      "sdp": "v=0\r\no=..."
    }
  }
]
```

---

### パターン 4: CallKitがエラーを返す

**症状:**
```
❌ CallKitService: Failed to report incoming call
❌ CallKitService: Error: ...
```

**原因:**
- CallKitの権限がない
- Info.plistの設定が不足

**対処法:**
1. Info.plistに以下が設定されているか確認:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>voip</string>
</array>
```

2. Xcodeの Capabilities で "Background Modes" → "Voice over IP" がチェックされているか確認

3. デバイスを再起動

---

### パターン 5: CallKitは成功するが音が鳴らない

**症状:**
```
✅ CallKitService: Incoming call reported successfully
✅ CallKitService: CallKit UI should be visible now
```
ログは成功しているが、着信音が鳴らない

**原因:**
- デバイスが消音モード
- 音量が0
- おやすみモード

**対処法:**
1. **物理的な消音スイッチ**を確認（iPhoneの側面）
2. **音量ボタン**で音量を上げる
3. **設定 → 集中モード**をすべてオフ
4. **実機でテスト**（シミュレータでは音が鳴らない）

---

## 完全なログフロー例（成功時）

```
// アプリ起動
✅ CallKitService: Initialized
👤 ContentView: 現在のユーザーID: 10
🔍 ContentView: 着信監視を開始します
✅ NotificationService: Starting monitoring for user 10
✅ NotificationService: メッセージと着信のポーリングを開始します
✅ NotificationService: タイマー設定完了 - メッセージ: 2秒, 着信: 1秒

// 定期ポーリング（1秒ごと）
🔍 NotificationService: 着信チェック開始 - User ID: 10
🔍 NotificationService: 着信チェック完了 - checked: 50, found signals: 0

// 着信発生
🔍 NotificationService: 着信チェック開始 - User ID: 10
🔍 NotificationService: Signals found for callId 11-10: 1 signals
🔍 NotificationService: Signal data: [{"action":"offer","data":{"sdp":"v=0..."}}]
🔍 NotificationService: Signal action: offer
📞 NotificationService: 着信検出！ CallID: 11-10
📞 NotificationService: 発信者: 11 → 着信者: 10
📞 NotificationService: SDP length: 2345
📞 NotificationService: Caller name: rcc122
📞 NotificationService: Calling CallKitService.reportIncomingCall

// CallKit表示
📞 CallKitService: ========== INCOMING CALL ==========
📞 CallKitService: UUID: 12345678-1234-1234-1234-123456789abc
📞 CallKitService: Handle: rcc122
📞 CallKitService: Has Video: false
📞 CallKitService: Caller ID: 11
📞 CallKitService: Calling provider.reportNewIncomingCall...
✅ CallKitService: Incoming call reported successfully
✅ CallKitService: CallKit UI should be visible now
✅ NotificationService: CallKit completion handler called

// ユーザーが応答
📞 CallKitService: User answered call - UUID: 12345678-1234-1234-1234-123456789abc
📞 ContentView: CallKit answer for callerId: 11
✅ ContentView: Using cached offer from NotificationService
🔵 CallManager: Accepting incoming call from rcc122
```

---

## トラブルシューティングチェックリスト

実機でテストする前に、以下をすべて確認してください:

### アプリ設定
- [ ] ログインしている（認証トークンがある）
- [ ] NotificationServiceが開始されている
- [ ] CallKitServiceが初期化されている

### Xcode設定
- [ ] Capabilities → Push Notifications: ON
- [ ] Capabilities → Background Modes → Voice over IP: ON
- [ ] Info.plist → UIBackgroundModes → voip: 設定済み

### デバイス設定
- [ ] 消音モードOFF（物理スイッチ）
- [ ] 音量が0でない
- [ ] おやすみモードOFF
- [ ] 実機でテスト（シミュレータ不可）

### ネットワーク
- [ ] インターネット接続OK
- [ ] APIサーバーに接続できる
- [ ] 認証トークンが有効

---

## 次のステップ

1. **アプリを実機で起動**
2. **Xcodeコンソールを開く**
3. **相手から発信してもらう**
4. **上記のログを確認**
5. **該当するパターンを特定**
6. **対処法を実行**

ログを確認して、どのステップで止まっているか教えてください。
