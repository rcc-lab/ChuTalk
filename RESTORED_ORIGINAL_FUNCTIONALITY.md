# 元の機能を復元

**作成日時**: 2025年10月9日 18:30
**ステータス**: ✅ 復元完了

---

## 問題

私が古いポーリング機構を無効化してしまったことで、元々動作していたメッセージ通知とビデオ通話の機能を壊してしまいました。

---

## 復元した内容

### 1. ContentView.swift

**変更**: 無効化していた`notificationService.startMonitoring(userId: userId)`を元に戻しました。

```swift
private func startServices() {
    guard let userId = authService.currentUser?.id else { return }

    print("👤 ContentView: 現在のユーザーID: \(userId)")
    print("🔍 ContentView: 着信監視を開始します")

    // NotificationServiceで着信とメッセージを監視
    notificationService.startMonitoring(userId: userId)
    print("✅ ContentView: Started NotificationService monitoring for user \(userId)")
}
```

**効果**:
- ✅ メッセージのポーリング検出が復元
- ✅ ビデオ通話の着信検出が復元
- ✅ カスタム通知バナーの表示が復元

---

### 2. MessagingService.swift

**変更**: 追加したローカル通知の処理を削除しました。

**理由**: NotificationServiceのポーリング機構がメッセージ通知を処理するため、重複を避けるため。

---

## 残した改善点

以下の修正は元の動作を壊さないため、そのまま残しています：

### 1. サーバー側: answer保存の401エラー修正

**ファイル**: `/srv/chutalk/api/server.js`

**効果**: VoIP Push経由で起動したアプリがanswerをAPIに保存できるようになり、通話確立が成功するようになります。

### 2. iOS側: answerのポーリング機能

**ファイル**: `CallManager.swift`

**効果**: Socket.IOが接続していない場合でも、APIからanswerを取得して通話を確立できます。

### 3. iOS側: displayNameの送信

**ファイル**: `SocketService.swift`

**効果**: VoIP PushとメッセージPushに正しい発信者名が含まれます。

---

## 動作の仕組み（復元後）

### メッセージ通知

1. NotificationServiceが2秒ごとにAPIをポーリング
2. 新しいメッセージを検出
3. `hasNewMessage = true`を設定
4. システム音を再生（AudioServicesPlaySystemSound）
5. ContentViewがカスタム通知バナーを表示

### ビデオ通話着信

#### アプリ起動中
1. NotificationServiceが1秒ごとにAPIをポーリング
2. 着信（offer）を検出
3. CallKitで着信画面を表示

#### アプリ停止時
1. Signal ServerがVoIP Pushを送信
2. VoIPPushServiceが受信
3. CallKitで着信画面を表示
4. ユーザーが応答
5. APIからofferを取得
6. answerを作成・送信（Socket.IO + API保存）
7. 発信者側がAPIからanswerをポーリング取得
8. 通話確立

---

## テスト手順

### 1. アプリを再ビルド

```
Xcode:
Product → Clean Build Folder (Shift + Cmd + K)
Product → Build (Cmd + B)
Product → Run (Cmd + B)
```

### 2. メッセージ通知をテスト

**アプリ起動中**:
1. 両デバイスでアプリを起動
2. ユーザー11がホーム画面または連絡先画面にいる
3. ユーザー10からメッセージ送信
4. **画面上部にカスタム通知バナーが表示される** ← 元の動作

**期待される結果**:
- ✅ カスタムバナー（青い背景）が表示
- ✅ 発信者名とメッセージ本文が表示
- ✅ システム音が鳴る

### 3. ビデオ通話をテスト

**アプリ起動中**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10に発信
3. 着信画面が表示されることを確認
4. 応答してビデオ通話

**期待される結果**:
- ✅ 着信画面が表示
- ✅ ビデオ通話が確立

**アプリ停止時**:
1. ユーザー10のアプリを停止
2. 30秒待つ
3. ユーザー11から発信
4. CallKit着信が表示
5. 応答してビデオ通話

**期待される結果**:
- ✅ CallKit着信画面が表示
- ✅ 応答後、ビデオ通話が確立（改善済み）

---

## まとめ

### 復元した機能
1. ✅ メッセージのポーリング検出
2. ✅ カスタム通知バナーの表示
3. ✅ ビデオ通話の着信検出（ポーリング）

### 追加した改善点
1. ✅ サーバー側: answer保存の401エラー修正
2. ✅ iOS側: answerポーリング機能
3. ✅ iOS側: displayName送信

---

**最終更新**: 2025年10月9日 18:30
**次回アクション**: アプリ再ビルド → テスト実施
