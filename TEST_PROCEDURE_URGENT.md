# 緊急テスト手順 - 修正の確認

**作成日時**: 2025年10月10日 00:30
**重要**: まずアプリ起動中のテストを実施してください

---

## 現状確認

### ✅ 確認済み
- CallManager.swift Line 482: `let hasVideo = detectVideoFromSDP(sdp)` - 正しく修正済み
- detectVideoFromSDP() Line 636: ログ出力あり - 正しく実装済み
- MessagingService.swift Line 110: Socket.IO送信 - 正しく修正済み

### ❌ 未確認
- 修正されたコードが実際に実行されているか
- Socket.IO経由の着信が正常に動作するか

---

## テスト手順（優先順位順）

### ⭐ テスト1: ビデオ通話着信（アプリ起動中）- 最優先

**目的**: 修正が正しく適用されているか確認

**手順**:
1. **両デバイスでアプリを起動**
2. 両方とも**ホーム画面にいる**（チャット画面ではない）
3. ユーザー11からユーザー10に**ビデオ通話**で発信
4. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Call ID: 11-10
   UUID: ...
   Has Video: true
```

**判定**:
- [ ] ✅ 上記のログが**全て**表示された → 修正は正しく動作しています
- [ ] ❌ `🔍 CallManager: Video track detected` が表示されない → 何か別の問題があります

**重要**: このログが表示されない場合、以下を報告してください:
1. `🔵 CallManager: Received offer` が表示されるか？
2. 表示される場合、その後のログは何か？
3. 表示されない場合、Socket.IO接続は成功しているか？（起動時のログで確認）

---

### ⭐ テスト2: 音声通話着信（アプリ起動中）

**手順**:
1. 両デバイスでアプリを起動
2. ユーザー11からユーザー10に**音声通話**で発信
3. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: No active video track in SDP
📞 CallManager: Reporting incoming call to CallKit
   Call ID: 11-10
   UUID: ...
   Has Video: false
```

**判定**:
- [ ] ✅ `Has Video: false` と表示された → 正常
- [ ] ❌ `Has Video: true` と表示された → 問題あり

---

### ⭐ テスト3: VoIP Push受信の詳細ログ（アプリ停止時）

**現在の問題**: VoIP Pushがデバイスに届いていない可能性

**確認方法**:

#### A. デバイスがXcodeに接続されている状態でテスト

**手順**:
1. ユーザー10のデバイスを**Xcodeに接続したまま**
2. Xcodeのコンソールを開く
3. アプリを**完全に停止**（スワイプアップ）
4. **30秒待つ**
5. ユーザー11からユーザー10に発信
6. Xcodeコンソールを確認

**期待されるログ**:
```
📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========
📞 VoIPPushService: Payload: {
    type = "call.incoming";
    callId = "11-10";
    fromUserId = 11;
    fromDisplayName = "rcc122";
    hasVideo = 1;
}
📞 VoIPPushService: Reporting incoming call to CallKit
   UUID: ...
   Caller: rcc122
   Caller ID: 11
   Has Video: true
✅ VoIPPushService: CallKit report completed
```

**もしこのログが表示されない場合、以下のいずれか**:
1. VoIP PushがAPNsから届いていない
2. PushKitの設定に問題がある
3. トークンの登録に問題がある

#### B. サーバーログとの照合

**サーバーログ（既に取得済み）**:
```
📞 sendVoipPush: Sending to user 10
   Type: call.incoming
   Call ID: 11-10
   From: rcc122 (11)
   Has Video: true
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
```

**iOS側のトークン（起動時のログ）**:
```
📞 VoIPPushService: VoIP Token: 27f7ca78a5062e65016521a89517e9301144bff8884f246121c3d968d7564052
```

**⚠️ 重要な発見**: トークンが一致していません！

- サーバーが送信したトークン: `9f739db8afff2029...`
- User 11のトークン（提供されたログ）: `27f7ca78a5062e65...`

**これは正常です**（User 10とUser 11は別のデバイス）。

しかし、**User 10のトークン**を確認する必要があります：
1. User 10のアプリを起動
2. ログで `📞 VoIPPushService: VoIP Token:` を確認
3. このトークンが `9f739db8afff2029...` と一致するか確認

---

## トラブルシューティング

### ケース1: `🔵 CallManager: Received offer` が表示されない（アプリ起動中）

**原因**: Socket.IO接続の問題

**確認**:
1. 起動時のログで以下を確認:
   ```
   ✅ SocketService: Socket connected
   ✅ SocketService: Registration message sent
   ```

2. もし接続されていない場合:
   - アプリを再起動
   - Signal Serverの状態を確認: `docker ps | grep signal`

### ケース2: `🔍 CallManager: Video track detected` が表示されない

**もし `🔵 CallManager: Received offer` は表示されるが、`🔍` ログが表示されない場合**:

これは非常に奇妙です。以下を確認してください:

1. **Xcodeで実際にビルドされたコードを確認**:
   - Xcode: Product → Show Build Folder in Finder
   - 最新のビルド時刻を確認
   - 現在時刻と一致しているか？

2. **複数のCallManager.swiftファイルが存在しないか確認**:
   ```bash
   find /Users/rcc/Documents/iosApp/iOS開発/ChuTalk -name "CallManager.swift"
   ```

3. **Xcodeのターゲット設定を確認**:
   - Xcode: Project Navigator → CallManager.swift を選択
   - 右側のFile Inspector → Target Membership
   - 「ChuTalk」にチェックが入っているか確認

### ケース3: VoIP Pushが全く届かない

**考えられる原因**:

#### A. APNs環境のミスマッチ

Xcode経由でインストールしたアプリは**Sandbox APNs**を使います。

**サーバー設定を確認**:
```bash
ssh takaoka@192.168.200.50
docker exec chutalk_api env | grep APNS
```

期待される値:
```
APNS_ENVIRONMENT=sandbox
APNS_BUNDLE_ID=rcc.takaokanet.com.ChuTalk
APNS_KEY_ID=...
APNS_TEAM_ID=...
```

**間違っている場合**:
1. `/srv/chutalk/.env` を編集
2. `docker-compose restart chutalk_api`

#### B. APNs認証キーの問題

**サーバーログでエラーを確認**:
```bash
docker logs chutalk_api 2>&1 | grep -i "apns\|error" | tail -50
```

エラーメッセージがある場合、それを報告してください。

#### C. PushKitの設定問題

**Xcodeで確認**:
1. Project → Targets → ChuTalk → Signing & Capabilities
2. 「Push Notifications」Capabilityが追加されているか
3. 「Background Modes」で「Voice over IP」にチェックが入っているか

**スクリーンショットを撮って確認してください**。

---

## 次のアクション（優先順位順）

### 1. まず **テスト1** を実施（アプリ起動中のビデオ通話） ⭐⭐⭐

このテストで、修正が正しく動作しているか確認できます。

**実施したら、以下を報告してください**:
- [ ] Xcodeコンソールの**全ログ**（`🔵 CallManager:` から始まる部分）
- [ ] 着信画面が表示されたか
- [ ] ビデオ通話/音声通話のどちらで表示されたか

### 2. **テスト2** を実施（アプリ起動中の音声通話）

**実施したら、以下を報告してください**:
- [ ] Xcodeコンソールの**全ログ**
- [ ] `Has Video: false` と表示されたか

### 3. **テスト3** を実施（VoIP Push受信）

**User 10のデバイスをXcodeに接続して実施**

**実施したら、以下を報告してください**:
- [ ] `📞 VoIPPushService: ========== INCOMING VOIP PUSH ==========` が表示されたか
- [ ] 表示されない場合、何かエラーログがあるか
- [ ] User 10のVoIPトークン（起動時のログ）

---

## 重要な注意事項

### テストの順序を守ってください

1. **アプリ起動中**のテストを先に実施
2. その後、**アプリ停止時**のテストを実施

理由：
- アプリ起動中のテストは、修正が正しく動作しているか確認できる
- アプリ停止時のテストは、VoIP Pushの設定を確認できる
- 順序を守ることで、問題を切り分けられる

### ログの完全性

**部分的なログではなく、必ず以下を含む完全なログを報告してください**:
- 着信の**前**のログ（Socket.IO接続状態など）
- 着信**時**のログ（offerを受信した部分）
- 着信の**後**のログ（CallKit報告など）

### トークンの確認

**User 10とUser 11の両方のトークンを確認してください**:
- User 10のVoIPトークン: ？（未確認）
- User 11のVoIPトークン: `27f7ca78a5062e65...`（確認済み）

サーバーが `9f739db8afff2029...` に送信している場合、これはUser 10のトークンのはずです。確認してください。

---

**最終更新**: 2025年10月10日 00:30
**次回アクション**: まず**テスト1**を実施して結果を報告してください
