# ChuTalk 通話機能修正内容

**修正日時**: 2025年10月10日

---

## 修正内容の概要

### 1. Info.plistに必須権限を追加

**問題**: カメラとマイクの使用許可がInfo.plistに記載されていなかった

**修正**: 以下の権限を追加

```xml
<key>NSCameraUsageDescription</key>
<string>ビデオ通話でカメラを使用します</string>
<key>NSMicrophoneUsageDescription</key>
<string>音声・ビデオ通話でマイクを使用します</string>
```

**影響**:
- ビデオ通話時にカメラへのアクセスが可能になる
- 音声・ビデオ通話時にマイクへのアクセスが可能になる
- 初回起動時に権限リクエストダイアログが表示される

---

### 2. CallManagerに無限ループ防止機能を追加

**問題**: WebRTC接続が失敗した際、`onDisconnected` コールバックが `endCall()` を呼び出し、それがさらに切断を引き起こす無限ループが発生していた

**修正内容**:

#### CallManager.swift に追加したコード:

```swift
// プライベート変数として追加
private var isSettingUpCall: Bool = false  // 通話セットアップ中フラグ（切断ループ防止）

// onDisconnected コールバックを修正
webRTCService.onDisconnected = { [weak self] in
    Task { @MainActor in
        // セットアップ中は切断コールバックを無視（無限ループ防止）
        guard let self = self, !self.isSettingUpCall else {
            print("⚠️ CallManager: Ignoring disconnect during setup")
            return
        }
        print("🔵 CallManager: Disconnect callback triggered")
        await self.endCall()
    }
}

// startCall() の開始時
self.isSettingUpCall = true  // セットアップ開始

// Offer送信完了後
self.isSettingUpCall = false  // セットアップ完了

// エラー時
self.isSettingUpCall = false  // エラー時もフラグをクリア

// acceptIncomingCall() にも同様の処理を追加
```

**影響**:
- 通話セットアップ中の意図しない切断イベントを無視
- 無限ループによる30回以上の連続cleanup防止
- より安定した通話確立

---

## テスト手順

### 前提条件

1. **実機が必要**: VoIP Push はシミュレータでは動作しません
2. **証明書の確認**: Apple Developer Portal で正しいBundle ID (`com.ksc-sys.rcc.ChuTalk`) が設定されていること
3. **サーバー側の設定**: `.env` ファイルで `APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk` になっていること

### ステップ1: アプリの再インストール

権限設定の変更を反映させるため、アプリを完全に再インストールします:

```bash
# Xcodeでクリーンビルド
# Product → Clean Build Folder (Cmd + Shift + K)
# Product → Build (Cmd + B)
# Product → Run (Cmd + R)
```

### ステップ2: 権限の確認

1. アプリ起動
2. **カメラとマイクの権限リクエスト**が表示されることを確認
3. **「許可」**を選択

**期待されるログ**:
```
✅ WebRTCService: Audio track added
✅ WebRTCService: Video track added
```

### ステップ3: ビデオ通話テスト

#### User 11から User 10へ発信:

1. User 11: アプリで User 10 を選択
2. 「ビデオ通話」ボタンをタップ

**期待されるログ (User 11側)**:
```
🔵 CallManager: Starting call to [表示名]
🔵 CallManager: Call ID: 11-10
🎥 WebRTCService: Setting up local tracks - isVideo: true
✅ WebRTCService: Audio track added
✅ WebRTCService: Video track added
🎥 WebRTCService: Creating offer - isVideo: true
✅ CallManager: Offer sent via Socket.io to [表示名]
```

**期待されるログ (User 10側)**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
📞 CallManager: Reporting incoming call to CallKit
✅ CallManager: CallKit report completed for Socket.io offer
```

3. User 10: CallKit の着信画面で「応答」をタップ

**期待されるログ (User 10側)**:
```
🔵 CallManager: Accepting incoming call from [表示名]
🎥 WebRTCService: Creating answer - isVideo: true
✅ CallManager: Answer sent via Socket.io to user 11
✅ CallManager: Incoming call accepted
```

4. **両方のデバイスで映像と音声が確認できること**

**期待されるログ (両側)**:
```
ICE connection state changed: 2  // connected
✅ CallManager: Call connected
```

### ステップ4: 音声通話テスト

1. 同様の手順で「音声通話」を選択
2. 映像なしで音声のみ通話できることを確認

### ステップ5: 通話終了テスト

1. 「終了」ボタンをタップ

**期待されるログ**:
```
🔵 CallManager: Ending call
🔵 WebRTCService: Closing connection and cleaning up resources
✅ WebRTCService: Cleanup complete
```

2. **cleanup が1回のみ実行されること**（30回以上繰り返されないこと）

---

## トラブルシューティング

### Q1: カメラ・マイクの権限リクエストが表示されない

**原因**: アプリが既にインストールされており、Info.plistの変更が反映されていない

**解決方法**:
1. デバイスからアプリを完全削除
2. デバイスを再起動
3. Xcode で Clean Build Folder → Build → Run

### Q2: ビデオ通話を開始するとすぐに切断される

**症状**:
```
🔵 WebRTCService: Closing connection and cleaning up resources
✅ WebRTCService: Cleanup complete
[繰り返し]
```

**原因**:
- カメラ・マイクの権限が拒否されている
- WebRTC接続がICEサーバーに到達できない

**解決方法**:
1. **設定 → ChuTalk → カメラ/マイク**で権限を確認
2. サーバーのTURN/STUNサーバーが正常に動作しているか確認
3. ネットワーク接続を確認

### Q3: CallManager のログが表示されない

**症状**:
```
🎥 WebRTCService: Setting up local tracks - isVideo: true
✅ WebRTCService: Audio track added
```
しかし、`🔵 CallManager: Starting call to ...` が表示されない

**原因**: UIから CallManager.startCall() が呼び出されていない

**解決方法**:
1. ChatView.swift または ContactsListView.swift の call ボタンが正しく実装されているか確認
2. `@ObservedObject private var callManager = CallManager.shared` が正しく設定されているか確認
3. Xcodeでブレークポイントを設定して startCall() が呼ばれているか確認

### Q4: Socket.IO 接続エラー

**症状**:
```
❌ SocketService: Socket error - ...
```

**解決方法**:
1. サーバーが起動しているか確認
2. Constants.swift の `socketURL` が正しいか確認
3. サーバーのログで WebSocket 接続を確認

---

## 既知の制限事項

### アプリ停止時の着信 (VoIP Push)

**現在の状態**: 未実装

**症状**: アプリを完全に終了すると着信を受けることができない

**理由**: VoIP Push は送信されているがデバイスが受信していない可能性

**次の作業**: 別ドキュメント `VOIP_PUSH_IMPLEMENTATION.md` を参照

---

## 次のステップ

1. ✅ **通話機能の復元** (このドキュメントで完了)
2. ⏳ **VoIP Push の実装** (次のタスク)
   - デバイスのAPNs接続診断
   - iOS 13+ VoIP Push ブロックの調査
   - 代替デバイスでのテスト

---

**最終更新**: 2025年10月10日
