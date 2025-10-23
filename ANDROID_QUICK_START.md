# ChuTalk Android版 クイックスタートガイド

## 🎯 Claude Code用の簡潔な指示書

### 前提条件
- ✅ Android Studioでプロジェクト作成済み
  - Name: ChuTalk
  - Package: com.rcclab.chutalk
  - Language: Kotlin
  - Minimum SDK: API 23

### Claude Codeへの最初の指示

新しいフォルダでClaude Codeを起動したら、以下をコピー＆ペーストしてください：

```
ChuTalk Androidアプリを開発します。iOS版の機能をAndroidに移植します。

# プロジェクト情報
- パッケージ名: com.rcclab.chutalk
- 言語: Kotlin
- Minimum SDK: API 23
- サーバー: https://chutalk.ksc-sys.com

# 詳細な仕様書
以下のファイルを読んで、iOS版の実装を参照してください：
/Users/rcc/Documents/iosApp/iOS開発/ChuTalk/ChuTalk/ANDROID_DEVELOPMENT_GUIDE.md

# 実装する機能（優先順位順）
1. 利用規約画面（App Store審査対応）
2. ログイン・登録画面
3. 連絡先一覧
4. チャット機能
5. 通報・ブロック機能（App Store審査対応）
6. WebRTC ビデオ通話
7. Socket.IO リアルタイム通信
8. FCM プッシュ通知

# 最初のステップ
Phase 1（プロジェクトセットアップ）から開始してください。

Phase 1の内容：
1. build.gradle.kts に依存関係を追加
2. Constants.kt を作成
3. AndroidManifest.xml を更新
4. PreferenceManager.kt を作成
5. 基本的なプロジェクト構造を構築

実装を開始してください。
```

## 📁 Android Studioプロジェクトの推奨場所

```
/Users/rcc/Documents/iosApp/Android開発/ChuTalk/
```

このディレクトリでClaude Codeを起動してください。

## 🔄 開発フロー

### 1日目: 基本セットアップ
```
"Phase 1を実装してください"
→ 依存関係、Constants、基本構造

"Phase 2を実装してください"
→ データモデル、Repository、API Client
```

### 2日目: 認証とUI
```
"Phase 3を実装してください"
→ 利用規約、ログイン、登録画面

"Phase 4を実装してください"
→ メイン画面、連絡先、チャット
```

### 3日目: リアルタイム通信
```
"Phase 5を実装してください"
→ Socket.IO、FCM プッシュ通知
```

### 4日目: 通話機能
```
"Phase 6を実装してください"
→ WebRTC、通話画面
```

### 5日目: テスト・調整
```
"Phase 7を実装してください"
→ テスト、デバッグ、最終調整
```

## 🧪 テスト用アカウント

iOS版と同じアカウントでテストできます：
- ユーザー1: `rcc122` / `rcc122`
- ユーザー2: `kohei.t` / `kohei0617`

## 📋 チェックリスト

各Phaseが完了したら確認：

### Phase 1 完了確認
- [ ] build.gradle.kts に全依存関係追加済み
- [ ] Constants.kt 作成済み
- [ ] AndroidManifest.xml 更新済み
- [ ] プロジェクトがビルドできる

### Phase 2 完了確認
- [ ] User, Contact, Message, Report, Block モデル作成済み
- [ ] ApiService インターフェース作成済み
- [ ] AuthRepository 作成済み
- [ ] PreferenceManager 作成済み

### Phase 3 完了確認
- [ ] 利用規約画面が表示できる
- [ ] ログイン機能が動作する
- [ ] 登録機能が動作する
- [ ] トークンがSharedPreferencesに保存される

### Phase 4 完了確認
- [ ] 連絡先一覧が表示できる
- [ ] チャット画面でメッセージ送受信できる
- [ ] 通報ダイアログが表示できる
- [ ] ブロック機能が動作する

### Phase 5 完了確認
- [ ] Socket.IO接続が確立できる
- [ ] リアルタイムでメッセージを受信できる
- [ ] FCM トークンがサーバーに送信される
- [ ] プッシュ通知が受信できる

### Phase 6 完了確認
- [ ] WebRTC接続が確立できる
- [ ] ビデオ通話ができる
- [ ] 音声ミュート・カメラON/OFFができる
- [ ] 通話終了ができる

### Phase 7 完了確認
- [ ] 全機能がiOS版と同等に動作する
- [ ] エラーハンドリングが適切
- [ ] Google Play審査準備完了

## 🚨 トラブルシューティング

### ビルドエラーが出る場合
```
"build.gradle.ktsのエラーを修正してください"
```

### 通信エラーが出る場合
```
"ネットワークエラーのログを確認して、APIリクエストを修正してください"
```

### WebRTCが動作しない場合
```
"WebRTCの権限とセットアップを確認してください"
```

## 📞 サポート

詳細な仕様や疑問点があれば：
```
"ANDROID_DEVELOPMENT_GUIDE.md の[該当セクション]について詳しく教えてください"
```

または：
```
"iOS版の[ファイル名]の実装をAndroidに移植してください"
```

---

**準備ができたら、上記の「Claude Codeへの最初の指示」をコピー＆ペーストして開始してください！**
