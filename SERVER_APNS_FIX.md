# サーバー側APNs設定の修正手順

**作成日時**: 2025年10月10日
**問題**: DeviceTokenNotForTopic エラーによりVoIP Push通知が届かない

---

## 問題の詳細

### 現在の状況

iOSアプリのBundle IDを変更したため、サーバーのAPNs証明書と不一致が発生しています：

- **Apple Developer Portal**: `com.ksc-sys.rcc.ChuTalk`
- **Xcode（修正後）**: `com.ksc-sys.rcc.ChuTalk` ✅
- **サーバーAPNs設定**: `rcc.takaokanet.com.ChuTalk` ❌

### エラーログ

```
📞 sendVoipPush: Sending to token a8d6eb067dee41c3...
❌ sendVoipPush: Failed: { reason: 'DeviceTokenNotForTopic' }
📞 sendVoipPush: Sending to token 9f739db8afff2029...
✅ sendVoipPush: Sent successfully
```

**原因**: 新しいトークン（a8d6eb...）は新Bundle ID用ですが、サーバーのAPNs証明書は旧Bundle ID用のため、APNsが拒否します。

---

## 修正手順

### ステップ1: サーバーにSSH接続

```bash
ssh ユーザー名@サーバーアドレス
```

### ステップ2: .envファイルを編集

ChuTalkのAPIサーバーの設定ファイルを探します：

```bash
# docker-composeファイルの場所を確認
find ~ -name "docker-compose.yml" | grep chutalk

# または
cd /srv/chutalk  # サーバーのインストール場所によって異なる
```

.envファイルを編集：

```bash
nano .env
```

### ステップ3: APNs Bundle IDを更新

以下の設定を探して修正してください：

**修正前**:
```env
APNS_BUNDLE_ID=rcc.takaokanet.com.ChuTalk
```

**修正後**:
```env
APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk
```

### ステップ4: APNs認証キー/証明書の確認

APNsの認証方式を確認してください。2つの方式があります：

#### 方式A: APNs認証キー（推奨）

```env
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=YYYYYYYYYY
APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8
APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk
```

**確認事項**:
- AuthKey_XXXXXXXXXX.p8 ファイルが存在するか
- このキーはApple Developer Portalでどのアプリ用に作成されたか

#### 方式B: APNs証明書

```env
APNS_CERT_PATH=/path/to/cert.pem
APNS_KEY_PATH=/path/to/key.pem
APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk
```

**確認事項**:
- 証明書ファイルが存在するか
- 証明書がどのBundle ID用に発行されたか

### ステップ5: APNs認証キー/証明書の再発行（必要な場合）

もしAPNsキー/証明書が旧Bundle ID専用の場合、新しいものを作成する必要があります。

#### Apple Developer Portalでの作業

1. https://developer.apple.com/account にアクセス
2. **Certificates, Identifiers & Profiles** → **Keys**
3. **+** ボタンをクリック
4. **Apple Push Notifications service (APNs)** にチェック
5. 名前を入力（例: "ChuTalk VoIP Push Key"）
6. **Continue** → **Register**
7. **AuthKey_XXXXXXXXXX.p8** ファイルをダウンロード
8. **Key ID** と **Team ID** をメモ

**重要**:
- 認証キーは一度しかダウンロードできません
- 安全な場所に保管してください
- Key IDとTeam IDは後で必要です

#### サーバーにアップロード

```bash
# ローカルマシンから
scp AuthKey_XXXXXXXXXX.p8 ユーザー名@サーバー:/srv/chutalk/certs/

# サーバー側で権限設定
chmod 600 /srv/chutalk/certs/AuthKey_XXXXXXXXXX.p8
```

#### .envファイルを更新

```env
APNS_KEY_ID=XXXXXXXXXX  # Apple Developer Portalで表示されたKey ID
APNS_TEAM_ID=YYYYYYYYYY  # Team ID
APNS_KEY_PATH=/srv/chutalk/certs/AuthKey_XXXXXXXXXX.p8
APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk
APNS_PRODUCTION=false  # 開発環境の場合
```

### ステップ6: Dockerコンテナを再起動

設定変更を反映させるため、APIサーバーを再起動します：

```bash
cd /srv/chutalk  # docker-compose.ymlがある場所

# APIサーバーのみ再起動
docker-compose restart api

# または、全コンテナを再起動
docker-compose down
docker-compose up -d
```

### ステップ7: ログで確認

```bash
# APIサーバーのログを確認
docker logs -f chutalk_api

# 以下のようなログが表示されれば成功
# ✅ APNs configured with bundle ID: com.ksc-sys.rcc.ChuTalk
```

---

## テスト手順

### ステップ1: 古いデバイストークンをクリア（オプション）

データベースから古いトークンを削除すると、テストが明確になります：

```bash
# PostgreSQLに接続
docker exec -it chutalk_postgres psql -U chutalk_user -d chutalk_db

# User 10の古いトークンを削除
DELETE FROM device_tokens WHERE user_id = 10 AND voip_device_token = '9f739db8afff2029...';

# 確認
SELECT user_id, voip_device_token FROM device_tokens WHERE user_id = 10;

# 終了
\q
```

### ステップ2: iOSアプリで再ログイン

1. iOSアプリを起動
2. ログアウト
3. User 10（rcc123）でログイン
4. 新しいVoIPトークンがアップロードされることを確認

**期待されるログ（iOS側）**:
```
📞 VoIPPushService: VOIP TOKEN UPDATED
✅ NotificationsService: Device tokens uploaded successfully
```

**期待されるログ（サーバー側）**:
```
✅ Device tokens updated for user 10
   VoIP Token: a8d6eb067dee41c3...
```

### ステップ3: アプリを停止して着信テスト

1. **User 10のデバイス**: アプリを完全に終了（スワイプして閉じる）
2. **User 11のデバイス**: User 10にビデオ通話で発信
3. **サーバーログを確認**:

**期待されるログ**:
```
📞 sendVoipPush: Sending to user 10
📞 sendVoipPush: Sending to token a8d6eb067dee41c3...
✅ sendVoipPush: Sent successfully
```

4. **User 10のデバイス**: 着信画面が表示されるか確認

---

## トラブルシューティング

### Q1: APNs認証キーはどこで確認できますか？

**回答**:
Apple Developer Portal → Certificates, Identifiers & Profiles → Keys

既存のキーがあれば、Key IDとTeam IDが表示されます。
ただし、.p8ファイルは再ダウンロードできないため、紛失した場合は新しいキーを作成する必要があります。

### Q2: 証明書と認証キー、どちらを使うべきですか？

**回答**:
APNs認証キー（.p8）を推奨します。理由：
- 複数のアプリで使用可能
- 有効期限なし
- 管理が簡単

証明書は1年ごとに更新が必要です。

### Q3: 開発環境と本番環境でAPNs設定は異なりますか？

**回答**:
はい。`APNS_PRODUCTION`環境変数で切り替えます：
- **開発環境**: `APNS_PRODUCTION=false`
- **本番環境**: `APNS_PRODUCTION=true`

認証キー自体は同じものを使用できます。

### Q4: DeviceTokenNotForTopic エラーが続く場合

**チェックリスト**:
- [ ] .envファイルのAPNS_BUNDLE_IDが `com.ksc-sys.rcc.ChuTalk` になっているか
- [ ] APIサーバーを再起動したか
- [ ] APNs認証キー/証明書がApple Developer Portalのチームと一致しているか
- [ ] iOSアプリのBundle IDが `com.ksc-sys.rcc.ChuTalk` になっているか
- [ ] iOSアプリで再ログインして新しいトークンを送信したか

---

## まとめ

**必須作業**:
1. サーバーの.envファイルで `APNS_BUNDLE_ID=com.ksc-sys.rcc.ChuTalk` に変更
2. APIサーバーを再起動
3. iOSアプリで再ログインして新トークンを送信
4. 着信テスト

**オプション作業**:
- 古いデバイストークンをデータベースから削除
- APNs認証キーを再発行（旧Bundle ID専用の場合）

---

**最終更新**: 2025年10月10日
