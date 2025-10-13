# VoIP Push通話確立の重大な修正

**作成日時**: 2025年10月9日 17:00
**重要度**: 🔴 **最重要** - 通話機能の根本的な問題を修正

---

## 🐛 発見された問題

### 問題: VoIP Pushで起動した時に通話が確立しない

**根本原因**:
VoIP Pushでアプリが起動した直後、Socket.IOがまだ接続していないため、着信側が送信するanswerが発信者に届かない。

```
[従来のフロー - 失敗]
1. 発信者: offerを送信 → Signal Server → VoIP Push
2. 着信者: アプリ起動（Socket.IO接続中...）
3. 着信者: answerを送信 → ❌ Socket.IO未接続のため送信失敗
4. 発信者: answerを受信できず → ❌ 通話確立失敗
```

**影響範囲**:
- ❌ アプリ停止時の着信 → 通話が確立しない
- ❌ バックグラウンド時の着信（Socket.IO切断後） → 通話が確立しない
- ✅ アプリ起動時の着信 → 正常動作（Socket.IO接続済み）

---

## ✅ 修正内容

### 1. Answer送信の二重化（Socket.IO + API）

**修正ファイル**: `CallManager.swift`

着信側でanswerを作成した時、Socket.IO経由での送信に加えて、APIにも保存するようにしました。

```swift
// CallManager.acceptIncomingCall() 内
// Send answer via Socket.io (if connected)
socketService.sendAnswer(to: contact.id, sdp: answer.sdp)

// Also save answer to API (ensures delivery even if Socket.IO not connected yet)
if let myUserId = AuthService.shared.currentUser?.id,
   let callId = self.callId {
    try await APIService.shared.saveAnswer(callId: callId, sdp: answer.sdp, from: myUserId, to: contact.id)
}
```

**効果**:
- Socket.IOが接続している場合: 従来通り即座にanswerが届く
- Socket.IOが未接続の場合: APIに保存され、発信者側がポーリングで取得

---

### 2. Answer取得のポーリング機能追加

**修正ファイル**: `CallManager.swift`

発信側でofferを送信した後、3秒待ってからAPIを15秒間ポーリングし、answerを取得するようにしました。

```swift
// CallManager.startCall() 内
// Send offer via Socket.io
socketService.sendOffer(to: contact.id, sdp: offer.sdp)

// Start polling for answer from API (fallback if Socket.IO doesn't deliver)
Task {
    await pollForAnswer()
}

// CallManager.pollForAnswer() 新規追加
private func pollForAnswer() async {
    // Wait 3 seconds for Socket.IO answer first
    try? await Task.sleep(nanoseconds: 3_000_000_000)

    // Poll for up to 15 seconds
    for attempt in 1...15 {
        if let answerSDP = try await APIService.shared.getAnswerSDP(callId: callId) {
            await handleIncomingAnswer(sdp: answerSDP)
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    }
}
```

**ポーリング戦略**:
1. まず3秒待つ（Socket.IO経由でanswerが来る可能性が高い）
2. 3秒経ってもanswerを受信していなければ、APIからポーリング開始
3. 1秒ごとに最大15回ポーリング（合計18秒待つ）
4. Socket.IO経由でanswerを受信した場合、ポーリングを即座に停止

---

### 3. APIService拡張

**修正ファイル**: `APIService.swift`

answerを保存・取得するメソッドを追加しました。

```swift
func saveAnswer(callId: String, sdp: String, from: Int, to: Int) async throws {
    // POST /api/calls/signal/:callId
    // { action: "answer", data: { sdp, from, to } }
}

func getAnswerSDP(callId: String) async throws -> String? {
    // GET /api/calls/signal/:callId
    // Returns answer.sdp if exists
}
```

**サーバー側対応**:
Signal Serverの既存エンドポイント `/api/calls/signal/:callId` が既にanswerの保存に対応しているため、サーバー側の変更は不要です。

---

## 🔄 新しい通話確立フロー

### アプリ停止時の着信（VoIP Push）

```
[修正後のフロー - 成功]
1. 発信者: offerを送信 → Signal Server
2. Signal Server: ユーザー検出 → APIにoffer保存 → VoIP Push送信
3. 着信者: VoIP Push受信 → CallKit表示 → ユーザーが応答
4. 着信者: アプリ起動 → Socket.IO接続開始（まだ未完了）
5. 着信者: APIからoffer取得 → answerを作成
6. 着信者: ✅ Socket.IO経由でanswerを送信（失敗してもOK）
7. 着信者: ✅ APIにanswerを保存（確実に保存）
8. 発信者: Socket.IO経由でanswerを待つ（3秒）
9. 発信者: 3秒経過 → ✅ APIからanswerをポーリング開始
10. 発信者: ✅ APIからanswerを取得 → WebRTC接続確立
11. ✅ 通話成功！
```

### アプリ起動時の着信（Socket.IO）

```
[修正後のフロー - 成功]
1. 発信者: offerを送信 → Signal Server → Socket.IO
2. 着信者: Socket.IO経由でoffer受信
3. 着信者: answerを作成
4. 着信者: ✅ Socket.IO経由でanswerを送信（即座に届く）
5. 着信者: ✅ APIにもanswerを保存（念のため）
6. 発信者: ✅ Socket.IO経由でanswerを受信（3秒以内）
7. 発信者: ポーリングタスクが自動停止（answerを既に受信済みと検出）
8. ✅ 通話成功！（従来通り）
```

---

## 📋 テスト手順

### 事前準備

1. **アプリを再ビルド**
   ```
   Xcode:
   Product → Clean Build Folder (Shift + Cmd + K)
   Product → Build (Cmd + B)
   Product → Run (Cmd + R)
   ```

2. **両デバイスで再インストール** （推奨）

3. **ログイン確認**
   - 両デバイスで正常にログインできること

---

### テスト1: アプリ起動時の通話（Socket.IO） - 回帰テスト

**目的**: 従来の動作が壊れていないことを確認

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11がユーザー10に発信
3. 応答してビデオ通話

**期待される結果**:
- ✅ 着信画面が即座に表示
- ✅ 応答後、ビデオ/音声が双方向で通じる
- ✅ Xcodeログに「Answer already received via Socket.IO, stopping API polling」が表示

---

### テスト2: アプリ停止時の通話（VoIP Push） - ⚠️ 最重要

**目的**: VoIP Push経由の通話確立を確認

**手順**:
1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. **30秒待つ**（Socket.IO切断を確実にするため）
3. ユーザー11がユーザー10に発信
4. ユーザー10でCallKit着信画面が表示されることを確認
5. 応答ボタンをタップ
6. ビデオ通話画面が表示されることを確認
7. 双方向で音声・映像が通じることを確認

**期待される結果**:
- ✅ CallKit着信画面が表示される（ロック画面でも）
- ✅ 応答すると自動的にアプリが起動
- ✅ 数秒後、ビデオ通話画面が表示される
- ✅ 双方向で音声・映像が通じる

**Xcodeログ（ユーザー11 - 発信者）**:
```
✅ CallManager: Offer sent via Socket.io to User 10
🔍 CallManager: Polling API for answer (attempt 1/15)...
🔍 CallManager: Polling API for answer (attempt 2/15)...
✅ CallManager: Found answer in API! Processing...
✅ CallManager: Received answer
✅ CallManager: WebRTC connection established
```

**Xcodeログ（ユーザー10 - 着信者）**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 CallKitProvider: reportIncomingCall
📞 ContentView: ========== CALLKIT ANSWER ==========
📞 ContentView: Fetching offer SDP from API...
✅ ContentView: Found offer SDP
📞 CallManager: Accepting incoming call
❌ SocketService: Cannot send answer - socket not connected（正常）
✅ CallManager: Answer also saved to API for callId: 11-10
```

---

### テスト3: バックグラウンド時の通話

**目的**: バックグラウンド状態での動作確認

**手順**:
1. ユーザー10のアプリを起動
2. ホームボタンを押してバックグラウンド化
3. **画面をロック**
4. **30秒待つ**
5. ユーザー11から発信

**期待される結果**:
- ケースA（Socket.IO接続中）: Socket.IO経由で即座に着信
- ケースB（Socket.IO切断後）: VoIP Push → テスト2と同じフロー

---

## 🐛 トラブルシューティング

### 通話が確立しない場合

#### 1. Xcodeログを確認（発信者側）

**正常なログ**:
```
✅ CallManager: Offer sent via Socket.io
🔍 CallManager: Polling API for answer (attempt X/15)...
✅ CallManager: Found answer in API! Processing...
✅ CallManager: Received answer
```

**異常なログ**:
```
⚠️ CallManager: No answer received after 18 seconds
```
→ 着信側でanswerが作成されていない可能性

#### 2. Xcodeログを確認（着信者側）

**正常なログ**:
```
✅ ContentView: Found offer SDP
📞 CallManager: Accepting incoming call
✅ CallManager: Answer also saved to API for callId: 11-10
```

**異常なログ**:
```
❌ ContentView: No offer SDP found
```
→ Signal Serverがofferを保存していない可能性

#### 3. サーバーログを確認

**Signal Server**:
```bash
docker logs -f chutalk_signal
```

**期待されるログ**:
```
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
✅ [signal] Saved offer to API for callId: 11-10
📞 Sending VoIP Push to user 10
✅ VoIP Push sent to user 10
```

**API Server**:
```bash
docker logs -f chutalk_api
```

**期待されるログ**:
```
POST /api/calls/signal/11-10 200（offer保存）
POST /api/internal/push/call 200（VoIP Push送信）
POST /api/calls/signal/11-10 200（answer保存 - iOSから）
GET /api/calls/signal/11-10 200（answerポーリング - iOSから）
```

---

### 音声・映像が通じない場合

#### 1. WebRTC接続状態を確認

**Xcodeログ**:
```
✅ CallManager: ICE connection state: connected
```

#### 2. ネットワーク環境を確認

- Wi-Fi接続を確認
- ファイアウォール設定を確認
- STUN/TURNサーバーの設定を確認（WebRTCService.swift）

#### 3. マイク・カメラの権限を確認

```
設定 → ChuTalk → マイク: ✅
設定 → ChuTalk → カメラ: ✅
```

---

## メッセージ通知について

**現状**:
- ✅ Socket.IO経由でメッセージを受信 → 正常に表示される
- ⚠️ アプリ停止時のメッセージPush通知 → サーバー側は送信済み、iOS側で受信確認が必要

**確認手順**:
1. ユーザー10のアプリを停止
2. ユーザー11からメッセージ送信
3. Signal Serverログを確認:
   ```
   [signal] user 10 is offline, sending message push
   ✅ Message Push sent to user 10
   ```
4. API Serverログを確認:
   ```
   📤 sendMessagePush: Sending to user 10
   ✅ sendMessagePush: Sent successfully
   ```
5. ユーザー10のデバイスで通知が表示されるか確認

**通知が表示されない場合**:
- APNsトークンが登録されているか確認
- 通知権限を確認
- APNs証明書の有効期限を確認

---

## 📊 変更ファイル一覧

### 修正したファイル

1. **CallManager.swift**
   - `acceptIncomingCall()`: answerをAPIにも保存
   - `startCall()`: answerポーリングを開始
   - `pollForAnswer()`: 新規メソッド追加

2. **APIService.swift**
   - `saveAnswer()`: 新規メソッド追加
   - `getAnswerSDP()`: 新規メソッド追加

3. **ContentView.swift**
   - `startServices()`: 古いポーリング機構を無効化（コメントアウト）

### 変更なし（確認のみ）

- SocketService.swift: 自動再接続機能が正しく実装されている
- AuthService.swift: ログイン時にSocket.IO接続が開始される
- VoIPPushService.swift: VoIP Push受信処理が正しく実装されている
- Signal Server (server.js): offerとanswerの保存機能が実装済み
- API Server (server.js): `/api/calls/signal/:callId` エンドポイントが実装済み

---

## ✅ 次のステップ

1. **アプリを再ビルド** ← 必須
2. **テスト2を実行**（アプリ停止時の通話） ← 最重要
3. **結果を報告**:
   - 成功: どのテストケースが成功したか
   - 失敗: どのテストケースで失敗したか + Xcodeログ + サーバーログ

---

**最終更新**: 2025年10月9日 17:00
**次回アクション**: アプリ再ビルド → テスト実施 → 結果報告
