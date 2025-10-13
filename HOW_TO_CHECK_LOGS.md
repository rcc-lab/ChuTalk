# ログの確認方法

**作成日時**: 2025年10月10日 00:35

---

## 問題

メッセージ履歴のログが多すぎて、重要なログが見えない。

---

## 解決方法：Xcodeのログフィルタ機能を使う

### 方法1: フィルタを使う（推奨）

**手順**:
1. Xcodeのコンソール画面を開く
2. 下部のフィルタボックス（🔍検索アイコン）に以下を入力:
   ```
   CallManager: Received offer
   ```

3. これで、着信を受けた時のログだけが表示されます

**期待されるログ**:
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
```

または
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: No active video track in SDP
📞 CallManager: Reporting incoming call to CallKit
   Has Video: false
```

---

### 方法2: 複数のフィルタを試す

#### A. 着信関連のログだけ表示
フィルタ: `CallManager`

#### B. Socket.IOイベントだけ表示
フィルタ: `SocketService: Event received`

#### C. ビデオ判定のログだけ表示
フィルタ: `Video track`

---

## テスト手順（簡易版）

### ステップ1: ログをクリア

1. Xcodeコンソールで右クリック → **Clear Console**
2. または、ゴミ箱アイコンをクリック

### ステップ2: 着信テストを実施

1. フィルタに `CallManager` を入力
2. ユーザー11からユーザー10に**ビデオ通話**で発信
3. ログを確認

### ステップ3: 結果を確認

**以下のログが表示されるか確認してください**:

#### ケース1: 修正が適用されている場合
```
🔵 CallManager: Received offer from user 11 via Socket.io
🔍 CallManager: Video track detected in SDP (port: 9)
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
```

#### ケース2: 修正が適用されていない場合
```
🔵 CallManager: Received offer from user 11 via Socket.io
📞 CallManager: Reporting incoming call to CallKit
   Has Video: true
```
（`🔍 CallManager: Video track detected` が表示されない）

#### ケース3: Socket.IOで着信が来ていない場合
```
（何も表示されない）
```

---

## 報告してほしい情報

### 1. フィルタ `CallManager` での結果

**質問**:
- [ ] `🔵 CallManager: Received offer` が表示されましたか？
- [ ] `🔍 CallManager: Video track detected` が表示されましたか？
- [ ] `Has Video: true` または `Has Video: false` のどちらが表示されましたか？

### 2. フィルタ `Video track` での結果

**質問**:
- [ ] 何か表示されましたか？
- [ ] 表示された場合、完全なログをコピーしてください

### 3. 着信画面の動作

**質問**:
- [ ] CallKit着信画面が表示されましたか？
- [ ] ビデオ通話として表示されましたか？（カメラアイコン）
- [ ] 音声通話として表示されましたか？（電話アイコン）

---

## 注意事項

### ログのタイミング

**重要**: 通話が終了した後のログではなく、**着信を受けた瞬間のログ**を確認してください。

- ❌ 悪い例: `call-ended` イベントのログ（通話終了後）
- ✅ 良い例: `Received offer` のログ（着信を受けた瞬間）

### フィルタのリセット

フィルタを解除するには、フィルタボックスの「✕」をクリックしてください。

---

## 次のアクション

1. **Xcodeコンソールをクリア**
2. **フィルタに `CallManager` を入力**
3. **ビデオ通話で発信**
4. **ログを確認して報告**

以下を報告してください:
```
🔵 CallManager: Received offer が表示されたか: [ ] Yes [ ] No
🔍 CallManager: Video track detected が表示されたか: [ ] Yes [ ] No
Has Video: [ ] true [ ] false
着信画面: [ ] 表示された [ ] 表示されなかった
着信の種類: [ ] ビデオ通話 [ ] 音声通話
```

---

**最終更新**: 2025年10月10日 00:35
