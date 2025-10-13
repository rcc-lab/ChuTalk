# ビデオ通話と音声通話の着信修正

**作成日時**: 2025年10月10日 00:00
**ステータス**: ✅ 修正完了 → 再ビルド必須

---

## 問題

**症状**: ビデオ通話と音声通話を同じように着信できない

---

## 原因

### 発信側

発信UIは既に正しく実装されています：
- ContactsListView.swift (Line 194-199): ビデオ通話/音声通話を選択可能
- CallManager.startCall() (Line 132): isVideoフラグを正しく設定

### 着信側（問題箇所）

**CallManager.handleIncomingOffer()** (Line 482) で、単純な判定を使用していました：
```swift
// 修正前（不正確）
let hasVideo = sdp.contains("m=video")
```

**問題点**:
- SDPに`m=video`が含まれていても、portが0の場合は無効
- SDPに`a=inactive`属性がある場合は無効
- 音声通話でも`m=video 0`が含まれる場合がある

**結果**: 音声通話として発信しても、ビデオ通話として判定される場合がある

---

## 修正内容

### CallManager.swift (Line 482)

**修正前**:
```swift
// Detect video from SDP
let hasVideo = sdp.contains("m=video")
```

**修正後**:
```swift
// Detect video from SDP using accurate detection
let hasVideo = detectVideoFromSDP(sdp)
```

### detectVideoFromSDP()メソッド

このメソッドは既に実装済み（Line 600-637）で、以下を正確に判定します：
- `m=video`行のportが0でないか
- `a=inactive`属性がないか

```swift
private func detectVideoFromSDP(_ sdp: String) -> Bool {
    let lines = sdp.components(separatedBy: .newlines)
    var inVideoSection = false
    var videoPort: Int?

    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // m=video行を検出
        if trimmedLine.hasPrefix("m=video") {
            inVideoSection = true
            // m=video 9 RTP/SAVPF 96 の形式からportを抽出
            let components = trimmedLine.components(separatedBy: " ")
            if components.count >= 2, let port = Int(components[1]) {
                videoPort = port
            }
        } else if trimmedLine.hasPrefix("m=") {
            // 別のメディアセクションに入ったのでビデオセクション終了
            inVideoSection = false
        }

        // ビデオセクション内でa=inactive属性をチェック
        if inVideoSection && trimmedLine == "a=inactive" {
            print("🔍 CallManager: Video track is inactive in SDP")
            return false
        }
    }

    // videoPortが0でない場合、ビデオが有効
    if let port = videoPort, port > 0 {
        print("🔍 CallManager: Video track detected in SDP (port: \(port))")
        return true
    } else {
        print("🔍 CallManager: No active video track in SDP")
        return false
    }
}
```

---

## 動作フロー

### ビデオ通話の発信

```
ユーザー11がビデオ通話を選択
    ↓
CallManager.startCall(isVideo: true)
    ↓
WebRTCService.createOffer(isVideo: true)
    ↓
SDPに "m=video 9" が含まれる（port > 0）
    ↓
Socket.IO経由でSignal Serverに送信
    ↓
Signal Server: hasVideo = sdp.includes("m=video") → true
    ↓
【ケース1: 受信側オンライン】
  Signal Server → Socket.IO経由でユーザー10に送信
  ユーザー10: CallManager.handleIncomingOffer()
  hasVideo = detectVideoFromSDP(sdp) → true（port=9）
  CallKit: hasVideo=true で着信画面表示
    ↓
【ケース2: 受信側オフライン】
  Signal Server → VoIP Push送信（hasVideo: true）
  ユーザー10: VoIPPushService受信
  CallKit: hasVideo=true で着信画面表示
```

### 音声通話の発信

```
ユーザー11が音声通話を選択
    ↓
CallManager.startCall(isVideo: false)
    ↓
WebRTCService.createOffer(isVideo: false)
    ↓
SDPに "m=video 0" が含まれる（port = 0）または "a=inactive"
    ↓
Socket.IO経由でSignal Serverに送信
    ↓
Signal Server: hasVideo = sdp.includes("m=video") → true（portを見ていない）
    ↓
【ケース1: 受信側オンライン】
  Signal Server → Socket.IO経由でユーザー10に送信
  ユーザー10: CallManager.handleIncomingOffer()
  hasVideo = detectVideoFromSDP(sdp) → false（port=0）✅ 修正後
  CallKit: hasVideo=false で着信画面表示
    ↓
【ケース2: 受信側オフライン】
  Signal Server → VoIP Push送信（hasVideo: false）✅ 正しい
  ユーザー10: VoIPPushService受信
  CallKit: hasVideo=false で着信画面表示
```

---

## 期待される効果

### 修正前

| 発信タイプ | 着信表示 | 問題 |
|------------|----------|------|
| ビデオ通話 | ビデオ通話 | ✅ 正常 |
| 音声通話 | ビデオ通話 | ❌ 誤判定（portを見ていない） |

### 修正後

| 発信タイプ | 着信表示 | 判定方法 |
|------------|----------|----------|
| ビデオ通話 | ビデオ通話 | ✅ port > 0、inactive無し |
| 音声通話 | 音声通話 | ✅ port = 0、またはinactive |

---

## テスト手順

### 事前準備

**アプリを再ビルド（必須）**:
```
Xcode:
Product → Clean Build Folder (Shift + Cmd + K)
Product → Build (Cmd + B)
Product → Run (Cmd + R)
```

---

### テスト1: ビデオ通話の着信（アプリ起動中）⭐

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11の連絡先リストからユーザー10を選択
3. 電話アイコンをタップ → **「ビデオ通話」を選択**
4. ユーザー10で着信画面が表示されることを確認

**期待される動作**:
- ✅ CallKit着信画面が表示される
- ✅ 「〇〇さんからビデオ通話」と表示される
- ✅ カメラアイコンが表示される

**確認するログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
```

---

### テスト2: 音声通話の着信（アプリ起動中）⭐

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11の連絡先リストからユーザー10を選択
3. 電話アイコンをタップ → **「音声通話」を選択**
4. ユーザー10で着信画面が表示されることを確認

**期待される動作**:
- ✅ CallKit着信画面が表示される
- ✅ 「〇〇さんから音声通話」と表示される
- ✅ 電話アイコンが表示される（カメラアイコンではない）

**確認するログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: No active video track in SDP
📞 CallManager: Reporting incoming call to CallKit
   Has Video: false
```

---

### テスト3: ビデオ通話の着信（アプリ停止時）⭐

**手順**:
1. ユーザー10のアプリを完全に停止
2. 画面をオフにする
3. 1分待つ
4. ユーザー11がユーザー10に**ビデオ通話**で発信
5. ユーザー10の画面が自動的にオンになり、着信画面が表示されることを確認

**期待される動作**:
- ✅ 画面が自動的にオンになる
- ✅ CallKit着信画面が表示される
- ✅ 「〇〇さんからビデオ通話」と表示される
- ✅ 応答後、ビデオ通話画面が表示される
- ✅ 双方向でビデオ・音声が通じる

---

### テスト4: 音声通話の着信（アプリ停止時）⭐

**手順**:
1. ユーザー10のアプリを完全に停止
2. 画面をオフにする
3. 1分待つ
4. ユーザー11がユーザー10に**音声通話**で発信
5. ユーザー10の画面が自動的にオンになり、着信画面が表示されることを確認

**期待される動作**:
- ✅ 画面が自動的にオンになる
- ✅ CallKit着信画面が表示される
- ✅ 「〇〇さんから音声通話」と表示される
- ✅ 応答後、音声通話画面が表示される（ビデオなし）
- ✅ 双方向で音声が聞こえる

---

## トラブルシューティング

### Q1: 音声通話でもビデオ通話として表示される

**A**: 以下を確認してください:

1. **アプリを再ビルドしましたか？**
   - 必ず Clean Build Folder してから再ビルド

2. **ログで正しく判定されていますか？**
   ```
   🔍 CallManager: No active video track in SDP
   Has Video: false
   ```
   - 表示される → 修正が適用されています
   - 表示されない → アプリが再ビルドされていません

---

### Q2: VoIP Push経由の着信で、ビデオ/音声が正しく判定されない

**A**: Signal Serverのログを確認してください:

```bash
docker logs -f chutalk_signal | grep "offer"
```

**期待されるログ**:
```
[signal] offer from 11 to 10
[signal] user 10 is offline, saving offer to API and sending VoIP Push
hasVideo: true  （ビデオ通話の場合）
hasVideo: false （音声通話の場合）
```

Signal ServerがSDPから正しく判定していることを確認してください。

---

## まとめ

### 修正内容

1. ✅ **CallManager.handleIncomingOffer()**: 単純な`contains()`チェックから、正確な`detectVideoFromSDP()`に変更

### 期待される効果

1. ✅ **ビデオ通話**: ビデオ通話として正しく着信する
2. ✅ **音声通話**: 音声通話として正しく着信する
3. ✅ **アプリ起動中**: Socket.IO経由で正しく判定される
4. ✅ **アプリ停止時**: VoIP Push経由で正しく判定される

### 変更ファイル

- **CallManager.swift** (Line 482): `detectVideoFromSDP(sdp)`を使用

---

**最終更新**: 2025年10月10日 00:00
**次回アクション**:
1. アプリを再ビルド
2. テスト1-4を実行
3. 結果を報告
