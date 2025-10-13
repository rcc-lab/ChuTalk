# 着信問題のデバッグ手順

**作成日時**: 2025年10月10日 00:10

---

## 報告された問題

1. ❌ アプリを停止すると着信されない
2. ❌ ビデオ通話モードで着信できない

---

## デバッグ手順

### ステップ1: アプリ停止時の着信テスト

**準備**:
サーバーでログを監視します：

```bash
# ターミナル1: Signal Serverのログ
ssh takaoka@192.168.200.50
docker logs -f chutalk_signal 2>&1 | grep --line-buffered -E "offer|VoIP|offline"

# ターミナル2: API Serverのログ
ssh takaoka@192.168.200.50
docker logs -f chutalk_api 2>&1 | grep --line-buffered -E "sendVoipPush|Failed|Sent"
```

**テスト実行**:
1. ユーザー10のアプリを**完全に停止**（タスクマネージャーからスワイプアップ）
2. **1分間待つ**
3. ユーザー11からユーザー10に**ビデオ通話**で発信
4. サーバーログを確認
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
   From: ユーザー11の名前 (11)
   Has Video: true
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
```

**実際のログをここに記録してください**:

**Signal Serverログ**:
```
[ここにログを記録]
```

**API Serverログ**:
```
[ここにログを記録]
```

**ユーザー10のデバイス**:
- [ ] 着信画面が表示された
- [ ] 着信画面が表示されなかった

---

### ステップ2: ビデオ通話の着信テスト（アプリ起動中）

**テスト実行**:
1. 両デバイスでアプリを起動
2. ユーザー11からユーザー10に**ビデオ通話**で発信
3. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
📞 CallKitProvider: REPORTING INCOMING CALL
   Has Video: true
✅ CallKitProvider: Incoming call reported successfully
```

**実際のログをここに記録してください**:
```
[ここにログを記録]
```

**ユーザー10のデバイス**:
- [ ] 着信画面が表示された
- [ ] ビデオ通話として表示された（カメラアイコン）
- [ ] 音声通話として表示された（電話アイコン）
- [ ] 着信画面が表示されなかった

---

### ステップ3: 音声通話の着信テスト（アプリ起動中）

**テスト実行**:
1. 両デバイスでアプリを起動
2. ユーザー11からユーザー10に**音声通話**で発信
3. ユーザー10のXcodeコンソールログを確認

**期待されるログ（ユーザー10側）**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: No active video track in SDP
📞 CallManager: Reporting incoming call to CallKit
   Has Video: false
📞 CallKitProvider: REPORTING INCOMING CALL
   Has Video: false
✅ CallKitProvider: Incoming call reported successfully
```

**実際のログをここに記録してください**:
```
[ここにログを記録]
```

**ユーザー10のデバイス**:
- [ ] 着信画面が表示された
- [ ] 音声通話として表示された（電話アイコン）
- [ ] ビデオ通話として表示された（カメラアイコン）
- [ ] 着信画面が表示されなかった

---

## 診断フローチャート

```
アプリ停止時に着信しない
    ↓
サーバーログで「sendVoipPush: Sent successfully」が表示される？
    ↓ YES
    ├─→ VoIPトークンの問題またはAPNsの問題
    │   → ユーザー10のアプリを起動してログ確認
    │   → 「VoIP Token: [トークン]」が表示されているか
    ↓ NO
    ├─→ VoIP Pushが送信されていない
        → Signal Serverのログで「offline」が表示されているか確認

ビデオ通話モードで着信できない
    ↓
アプリ起動中のログで「Has Video: true」が表示される？
    ↓ YES
    ├─→ CallKitの問題
    │   → CallKitProviderのログ確認
    ↓ NO
    ├─→ SDP判定の問題
        → detectVideoFromSDP()のログ確認
        → 「Video track detected」が表示されるべき
```

---

## よくある原因

### 原因1: アプリが完全に停止していない

**症状**: バックグラウンドで動作しているため、Socket.IOがまだ接続されている

**対処法**:
1. タスクマネージャーでアプリを完全に終了
2. 1-2分待ってからテスト

### 原因2: VoIPトークンが登録されていない

**症状**: サーバーログで「No VoIP tokens found」が表示される

**対処法**:
1. アプリを起動
2. ログで「✅ VoIPPushService: VoIP Token: [トークン]」を確認
3. ログで「✅ NotificationsService: Device tokens uploaded successfully」を確認

### 原因3: APNs証明書の問題

**症状**: サーバーログで「sendVoipPush: Failed」が表示される

**対処法**:
- サーバーログのエラーメッセージを確認
- APNs環境（sandbox/production）を確認

---

## 次のアクション

上記のステップ1-3を実施して、以下の情報を報告してください：

1. **ステップ1のログ**（Signal Server + API Server）
2. **ステップ2のログ**（ユーザー10のXcode）
3. **ステップ3のログ**（ユーザー10のXcode）
4. **各テストの結果**（着信画面が表示されたか）

これらの情報があれば、問題の原因を特定できます。

---

**最終更新**: 2025年10月10日 00:10
