# VoIP Push完全リセット手順

**問題**: iOS 13以降、VoIP Pushを受信してCallKitを呼び出さないと、次回以降の配信がブロックされる

**作成日時**: 2025年10月10日

---

## 原因

iOS 13以降、VoIP Pushには厳格な制限があります：
- VoIP Pushを受信したら**必ずCallKitを呼び出す必要がある**
- 呼び出さないと、そのデバイスへのVoIP Push配信が永久にブロックされる
- 開発中のテストで、何度もVoIP Pushを受信してCallKitを呼び出さなかった場合、ブロックされる

参考：https://developer.apple.com/documentation/pushkit/pkpushregistrydelegate/2875784-pushregistry

---

## 完全リセット手順

### ステップ1: デバイスからアプリを完全削除

1. ホーム画面でChuTalkアイコンを長押し
2. **「Appを削除」** をタップ
3. **「削除」** を確認

### ステップ2: デバイスを再起動

1. 電源ボタン長押し → スライドで電源オフ
2. **30秒待つ**
3. 電源ボタン長押しで再起動

### ステップ3: Xcodeでクリーンビルド

```bash
# ターミナルで実行


```

Xcodeで：
1. **Product → Clean Build Folder** (Cmd + Shift + K)
2. **Product → Build** (Cmd + B)

### ステップ4: デバイスに再インストール

1. Xcode → **Product → Run** (Cmd + R)
2. デバイスにアプリがインストールされることを確認

### ステップ5: 初期設定

1. アプリを起動
2. 通知許可をリクエストされたら**「許可」**
3. User 10でログイン
4. **Xcodeコンソールで以下を確認**:

```
✅ VoIPPushService: PushKit registered
📞 VoIPPushService: VOIP TOKEN UPDATED
📞 VoIPPushService: VoIP Token: a8d6eb067dee41c3...
```

### ステップ6: 着信テスト

1. **User 10のアプリを完全に終了**（スワイプして閉じる）
2. **Xcodeコンソールの出力が止まることを確認**
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

## トラブルシューティング

### Q1: 再インストール後もVoIP Pushが届かない

**対処方法**:
1. デバイスの**設定 → 一般 → 転送またはiPhoneをリセット → すべてのコンテンツと設定を消去**
2. デバイスを初期化
3. 再度アプリをインストール

**注意**: これは最終手段です。データがすべて削除されます。

### Q2: 通常のAPNs通知は届くのに、VoIP Pushだけ届かない

**原因**: VoIP Push配信がブロックされている

**対処方法**: 上記の完全リセット手順を実施

### Q3: 別のデバイスでテスト

もし可能であれば、**別のデバイス**でテストしてください。
新しいデバイスであれば、VoIP Pushブロックの問題がないため、正常に動作するはずです。

---

## 予防策

開発中は以下に注意してください：

1. **VoIP Pushを受信したら、必ずCallKitを呼び出す**
2. **テスト時に何度もVoIP Pushを送信しない**（1回のテストで確認）
3. **コードを修正したら、必ずクリーンビルドして再インストール**

---

**最終更新**: 2025年10月10日
