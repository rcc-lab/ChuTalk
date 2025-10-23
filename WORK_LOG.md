# ChuTalk - App Store審査対応作業ログ

## 📋 プロジェクト概要
ChuTalkは、WebRTCを使用したビデオ通話・メッセージングアプリです。

**現在の状態:** App Store審査中（Build 31, Version 1.0）

## 🎯 App Store Guideline 1.2対応

### 実装した安全機能

#### 1. ✅ 利用規約（EULA）
- **実装日:** 2025-10-22
- **ファイル:**
  - `ChuTalk/Resources/TermsOfService.txt`
  - `ChuTalk/Views/TermsOfServiceView.swift`
  - `ChuTalk/Views/LoginView.swift`（利用規約同意フロー）
- **動作:**
  - 初回ログイン時、またはログアウト→再ログイン時に表示
  - ユーザーは同意しないとアプリを使用できない
  - 不適切なコンテンツ（ハラスメント、脅迫、ポルノ、違法行為など）を禁止する内容

#### 2. ✅ 通報機能
- **実装日:** 2025-10-22
- **ファイル:**
  - `ChuTalk/Models/Report.swift`
  - `ChuTalk/Views/ChatView.swift`（通報UI）
  - `ChuTalk/Services/APIService.swift`（通報API）
- **動作:**
  - メッセージを長押し → 「通報」を選択
  - 理由を選択（ハラスメント、スパム、不適切なコンテンツなど）
  - サーバーに送信され、データベースに保存
- **サーバー側エンドポイント:** `POST /api/reports`

#### 3. ✅ ブロック機能
- **実装日:** 2025-10-22
- **ファイル:**
  - `ChuTalk/Models/Block.swift`
  - `ChuTalk/Views/ChatView.swift`（ブロックUI）
  - `ChuTalk/Services/APIService.swift`（ブロックAPI）
- **動作:**
  - チャット画面右上のメニュー（⋮）→「ブロック」を選択
  - ブロックしたユーザーはメッセージ送信・通話ができなくなる
  - ブロックリストから解除も可能
- **サーバー側エンドポイント:**
  - `POST /api/blocks`（ブロック追加）
  - `GET /api/blocks`（ブロックリスト取得）
  - `DELETE /api/blocks/:userId`（ブロック解除）

#### 4. ✅ 24時間対応コミットメント
- **監視方法:** PostgreSQLデータベースの`reports`テーブルを確認
- **データベースクエリ例:**
  ```sql
  SELECT r.id, r.created_at, r.reason, r.status,
         reporter.username as reporter_username,
         reported.username as reported_username,
         m.content as message_content
  FROM reports r
  JOIN users reporter ON r.reporter_id = reporter.id
  JOIN users reported ON r.reported_user_id = reported.id
  LEFT JOIN messages m ON r.message_id = m.id
  ORDER BY r.created_at DESC;
  ```

## 🏗️ アーキテクチャ

### iOS App
- **バージョン:** 1.0
- **最新ビルド:** 31
- **対応iOS:** 15.0以降
- **依存関係:**
  - GoogleWebRTC (1.1.31999)
  - SocketIO (16.1.0)
  - KeychainSwift (20.0.0)

### Backend API
- **サーバー:** https://chutalk.ksc-sys.com
- **技術スタック:** Node.js + Express + PostgreSQL
- **エンドポイント:**
  - v1: 通常のエンドポイント（現在使用中）
  - v2: ブロック・フィルタリング対応エンドポイント（準備済み）

### データベーススキーマ
- **users**: ユーザー情報
- **messages**: メッセージ履歴
- **reports**: 通報データ
- **blocks**: ブロックリスト

## 📝 重要な設定

### Constants.swift
```swift
static let isAppStoreReviewBuild = false  // v1エンドポイント使用（Build 26の動作を維持）
```

### テストアカウント
- **アカウント1:** Username: `rcc122`, Password: `rcc122`
- **アカウント2:** Username: `kohei.t`, Password: `kohei0617`

## 🔧 修正履歴

### Build 29 → Build 30
1. iOS 15互換性修正（TermsOfServiceView.swift）
2. VoIP通話問題修正（v1エンドポイントに戻す）
3. 既読機能の簡素化（リトライロジック削除）

### Build 30 → Build 31
1. サーバー側通報・ブロックエンドポイント追加
2. 通報機能の動作確認・修正

## 📱 現在の動作状況

- ✅ ビデオ通話（アプリ未起動時も着信可能）
- ✅ メッセージ既読機能
- ✅ 通報機能
- ✅ ブロック機能
- ✅ 利用規約同意フロー

## 🚀 App Store審査状況

### 最新の対応（2025-10-23）
1. **審査チームからのフィードバック:**
   - 利用規約、通報、ブロック機能が見つからないとの指摘

2. **返信内容:**
   - Build 31に全機能実装済みであることを説明
   - 利用規約はログアウト→再ログイン時に表示されることを明記
   - 詳細なテスト手順を提供

3. **次のステップ:**
   - Apple Reviewチームの返信待ち
   - Build 31で再審査予定

## 📂 重要なファイル

### 新規追加ファイル
- `ChuTalk/Views/TermsOfServiceView.swift` - 利用規約画面
- `ChuTalk/Resources/TermsOfService.txt` - 利用規約テキスト
- `ChuTalk/Models/Report.swift` - 通報モデル
- `ChuTalk/Models/Block.swift` - ブロックモデル
- `ChuTalk/Utils/FileLogger.swift` - デバッグ用ログ
- `ChuTalk/Views/SplashScreenView.swift` - スプラッシュ画面
- `ChuTalk/Views/AppIconView.swift` - アプリアイコン表示

### 主要な変更ファイル
- `ChuTalk/Views/ChatView.swift` - 通報・ブロックUI追加
- `ChuTalk/Views/LoginView.swift` - 利用規約同意フロー追加
- `ChuTalk/Services/APIService.swift` - 通報・ブロックAPI追加
- `ChuTalk/Utils/Constants.swift` - v1/v2エンドポイント切り替え
- `Podfile` - コード署名設定追加

## 🛠️ トラブルシューティング

### コード署名エラー
**修正方法:** Podfileに以下を追加
```ruby
config.build_settings['CODE_SIGN_IDENTITY'] = ''
config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
```

### VoIP着信が動作しない
**原因:** v2エンドポイントへの変更
**修正方法:** `Constants.isAppStoreReviewBuild = false`に設定

### 通報機能が失敗する
**原因:** サーバー側エンドポイント未実装
**修正方法:** server.jsに通報・ブロックエンドポイント追加

## 📌 今後の予定

1. ⏳ App Store審査の結果待ち
2. ⏳ 審査通過後の一般公開
3. 📋 管理者用通報確認画面の実装（オプション）
4. 📋 v2エンドポイントの完全テストと移行

## 🔗 関連リソース

- **App Store Connect:** https://appstoreconnect.apple.com
- **TestFlight:** Build 31配布中
- **サーバー:** https://chutalk.ksc-sys.com
- **データベース:** PostgreSQL (Docker: chutalk_db)
- **APIサーバー:** Docker: chutalk_api

---

**最終更新:** 2025-10-23
**作成者:** Claude Code
**審査状態:** 審査準備完了（Build 31）
