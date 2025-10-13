# APNs通知テスト手順

**目的**: VoIP Pushの前に、通常のAPNs通知が正しく動作するか確認する

---

## テスト方法

### サーバー側でテスト送信

データベースに接続して、User 10に通常のAPNs通知を送信します：

```bash
# サーバーにSSH接続
ssh takaoka@192.168.200.50

# Node.jsコンソールを開く
docker exec -it chutalk_api node

# 以下のコードを実行
const apn = require('@parse/node-apn');

const provider = new apn.Provider({
  token: {
    key: '/certs/AuthKey_VLC43VS8N5.p8',
    keyId: 'VLC43VS8N5',
    teamId: '3KX7Q4LX88'
  },
  production: false
});

const notification = new apn.Notification();
notification.topic = 'com.ksc-sys.rcc.ChuTalk';
notification.sound = 'default';
notification.alert = { title: 'Test', body: 'APNs test message' };
notification.badge = 1;

// User 10のAPNsトークンを確認
// docker exec chutalk_db psql -U postgres -d chutalk -c "SELECT LEFT(token, 20) FROM devices WHERE user_id = 10;"

const token = 'ここにAPNsトークンを入力';
provider.send(notification, token).then(res => {
  console.log('Response:', JSON.stringify(res, null, 2));
}).catch(err => {
  console.error('Error:', err);
});
```

---

## 期待される結果

### 成功の場合

```json
{
  "sent": [
    {
      "device": "..."
    }
  ],
  "failed": []
}
```

User 10のデバイスに通知が表示される。

### 失敗の場合

```json
{
  "sent": [],
  "failed": [
    {
      "device": "...",
      "response": {
        "reason": "DeviceTokenNotForTopic"
      }
    }
  ]
}
```

**DeviceTokenNotForTopic**: APNs証明書とBundle IDが一致していない。

---

## 次のアクション

- **通常APNsが成功** → VoIP Push設定の問題を調査
- **通常APNsも失敗** → APNs認証キーまたはBundle ID設定の問題

---

**作成日時**: 2025年10月10日
