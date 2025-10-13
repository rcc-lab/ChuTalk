# CallKit着信の設定とテスト手順

## 実装内容

CallKitを使用した着信処理を実装しました。これにより、iOSの標準着信UIと着信音が使用されます。

## 着信の流れ

```
1. NotificationServiceが1秒ごとに着信をポーリング
   ↓
2. offerシグナルを検出
   ↓
3. CallKitService.reportIncomingCall()を呼び出し
   ↓
4. iOSの標準着信画面が表示される（着信音が鳴る）
   ↓
5. ユーザーが「応答」をタップ
   ↓
6. CallKitDelegateがContentViewに通知
   ↓
7. WebRTC接続を開始
   ↓
8. 通話開始
```

## デバッグログの確認

### 着信検出時
```
🔍 NotificationService: 着信チェック中 - User ID: 10
📞 NotificationService: 着信検出！ CallID: 11-10
📞 NotificationService: 発信者: 11 → 着信者: 10
📞 CallKitService: Reporting incoming call - UUID: xxx, Handle: rcc122
✅ CallKitService: Incoming call reported successfully
```

### 応答時
```
📞 CallKitService: User answered call - UUID: xxx
📞 ContentView: CallKit answer for callerId: 11
✅ ContentView: Using cached offer from NotificationService
🔵 CallManager: Accepting incoming call from rcc122
```

### 拒否時
```
📞 CallKitService: Call ended by user - UUID: xxx
📞 ContentView: CallKit end call
```

## トラブルシューティング

### 着信が表示されない

**確認1: ポーリングが動作しているか**
```
🔍 NotificationService: 着信チェック中 - User ID: 10
```
このログが5秒ごとに表示されていることを確認

**確認2: offerシグナルが来ているか**
相手から発信したときに以下のログが出るか確認:
```
📞 NotificationService: 着信検出！ CallID: 11-10
```

**確認3: CallKitが初期化されているか**
アプリ起動時に以下のログが出ることを確認:
```
✅ CallKitService: Initialized
```

### 着信音が鳴らない

**原因1: iPhoneが消音モード**
- 物理的な消音スイッチを確認
- 音量ボタンで音量を上げる

**原因2: マナーモード/おやすみモード**
- 設定 → 集中モード → すべてオフ

**原因3: CallKit設定**
CallKitServiceの初期化で以下が設定されていることを確認:
```swift
configuration.ringtoneSound = "Ringtone.caf"
```

### 応答できない

**確認1: offerが保存されているか**
応答時のログで以下が表示されるか確認:
```
✅ ContentView: Using cached offer from NotificationService
```

表示されない場合は:
```
⚠️ ContentView: No cached offer, fetching from API
```
APIからofferを取得する

**確認2: WebRTC接続エラー**
CallManagerのログでエラーを確認:
```
❌ CallManager: Failed to accept call - [エラー内容]
```

## テスト手順

### 準備
1. 2台のiPhoneまたは1台のiPhone + 1台のシミュレータ
2. 両方でログイン（例: User 10 と User 11）

### テスト1: 着信表示
1. User 11 から User 10 に発信
2. User 10 でCallKitの着信画面が表示されることを確認
3. 着信音が鳴ることを確認

### テスト2: 応答
1. 着信画面で「応答」をタップ
2. 通話画面に遷移することを確認
3. 音声・映像が通じることを確認

### テスト3: 拒否
1. 着信画面で「拒否」をタップ
2. 着信が終了することを確認

### テスト4: タイムアウト
1. 着信を30秒以上放置
2. 自動的に着信が終了することを確認

## 制限事項

### 現在の実装
- **ポーリング方式**: 1秒ごとにAPIをポーリング
- **遅延**: 最大1秒の遅延が発生する可能性

### 将来の改善
サーバーがVoIP Push通知を送信するようになれば:
1. リアルタイムで着信通知
2. バックグラウンド/アプリ終了時も着信可能
3. バッテリー消費の削減

その場合、VoIPPushServiceが自動的に動作します。

## カスタマイズ

### 着信音の変更
CallKitService.swiftで設定:
```swift
configuration.ringtoneSound = "custom_ringtone.caf" // カスタム着信音
```

### 表示名の変更
CallKitService.swiftで設定:
```swift
let configuration = CXProviderConfiguration(localizedName: "あなたのアプリ名")
```

### アイコンの変更
CallKitService.swiftで設定:
```swift
configuration.iconTemplateImageData = UIImage(named: "CallIcon")?.pngData()
```
