# ChuTalk Android版 開発ガイド（Claude Code用）

## 📋 プロジェクト情報

### 基本設定
- **プロジェクト名:** ChuTalk
- **パッケージ名:** com.rcclab.chutalk
- **言語:** Kotlin
- **Minimum SDK:** API 23 (Android 6.0 Marshmallow)
- **Target SDK:** API 34 (Android 14) 推奨
- **ビルドシステム:** Gradle (Kotlin DSL推奨)

### プロジェクト構成
```
ChuTalk/
├── app/
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/rcclab/chutalk/
│   │   │   │   ├── data/
│   │   │   │   │   ├── model/          # データモデル
│   │   │   │   │   ├── repository/     # リポジトリパターン
│   │   │   │   │   └── api/            # API クライアント
│   │   │   │   ├── ui/
│   │   │   │   │   ├── auth/           # ログイン・登録画面
│   │   │   │   │   ├── contacts/       # 連絡先一覧
│   │   │   │   │   ├── chat/           # チャット画面
│   │   │   │   │   ├── call/           # 通話画面
│   │   │   │   │   ├── settings/       # 設定画面
│   │   │   │   │   └── terms/          # 利用規約画面
│   │   │   │   ├── service/            # バックグラウンドサービス
│   │   │   │   │   ├── CallService.kt
│   │   │   │   │   ├── SocketService.kt
│   │   │   │   │   └── FCMService.kt
│   │   │   │   ├── utils/              # ユーティリティ
│   │   │   │   │   ├── Constants.kt
│   │   │   │   │   ├── PreferenceManager.kt
│   │   │   │   │   └── FileLogger.kt
│   │   │   │   ├── webrtc/             # WebRTC関連
│   │   │   │   │   ├── WebRTCClient.kt
│   │   │   │   │   └── PeerConnectionObserver.kt
│   │   │   │   └── MainActivity.kt
│   │   │   ├── res/
│   │   │   │   ├── layout/             # レイアウトXML
│   │   │   │   ├── values/             # strings.xml, colors.xml等
│   │   │   │   ├── drawable/           # アイコン・画像
│   │   │   │   └── raw/                # terms_of_service.txt
│   │   │   └── AndroidManifest.xml
│   │   └── test/
│   └── build.gradle.kts
├── gradle/
└── build.gradle.kts
```

## 🎯 iOS版との機能対応

### 実装必須機能（App Store審査対応と同等）

#### 1. 利用規約（EULA）
**iOS版対応ファイル:**
- `ChuTalk/Resources/TermsOfService.txt`
- `ChuTalk/Views/TermsOfServiceView.swift`

**Android版実装:**
```kotlin
// app/src/main/res/raw/terms_of_service.txt
- iOS版と同じ内容をコピー

// app/src/main/java/com/rcclab/chutalk/ui/terms/TermsOfServiceActivity.kt
class TermsOfServiceActivity : AppCompatActivity() {
    // 利用規約表示画面
    // 「同意する」ボタンで次へ進む
    // SharedPreferencesに同意状態を保存
}

// app/src/main/res/layout/activity_terms_of_service.xml
- ScrollView + TextView（利用規約テキスト）
- Button（同意するボタン）
```

#### 2. 認証機能
**iOS版対応ファイル:**
- `ChuTalk/Views/LoginView.swift`
- `ChuTalk/Views/RegisterView.swift`
- `ChuTalk/Services/AuthService.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/ui/auth/LoginActivity.kt
class LoginActivity : AppCompatActivity() {
    // ユーザー名・パスワード入力
    // POST /api/auth/login
    // トークンをSharedPreferencesに保存
}

// app/src/main/java/com/rcclab/chutalk/ui/auth/RegisterActivity.kt
class RegisterActivity : AppCompatActivity() {
    // ユーザー名・表示名・パスワード入力
    // POST /api/auth/register
}

// app/src/main/java/com/rcclab/chutalk/data/repository/AuthRepository.kt
class AuthRepository(private val apiService: ApiService) {
    suspend fun login(username: String, password: String): Result<AuthResponse>
    suspend fun register(username: String, displayName: String, password: String): Result<AuthResponse>
}
```

#### 3. 連絡先一覧
**iOS版対応ファイル:**
- `ChuTalk/Views/ContactsListView.swift`
- `ChuTalk/Services/APIService.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/ui/contacts/ContactsFragment.kt
class ContactsFragment : Fragment() {
    // RecyclerView で連絡先表示
    // GET /api/contacts
    // Socket.IO でオンライン状態をリアルタイム更新
}

// app/src/main/java/com/rcclab/chutalk/data/model/Contact.kt
data class Contact(
    val id: Int,
    val username: String,
    val displayName: String,
    val profileImageUrl: String?,
    val isOnline: Boolean,
    val isFavorite: Boolean
)
```

#### 4. チャット機能
**iOS版対応ファイル:**
- `ChuTalk/Views/ChatView.swift`
- `ChuTalk/Services/MessagingService.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/ui/chat/ChatActivity.kt
class ChatActivity : AppCompatActivity() {
    // RecyclerView でメッセージ表示
    // 長押しで「通報」メニュー表示
    // メニューから「ブロック」オプション
    // GET /api/messages?userId={userId}
    // POST /api/messages (メッセージ送信)
    // Socket.IO でリアルタイム受信
}

// app/src/main/java/com/rcclab/chutalk/data/model/Message.kt
data class Message(
    val id: Int,
    val senderId: Int,
    val receiverId: Int,
    val content: String,
    val timestamp: Long,
    val isRead: Boolean,
    val type: String = "text"
)
```

#### 5. 通報機能（App Store Guideline 1.2対応）
**iOS版対応ファイル:**
- `ChuTalk/Models/Report.swift`
- `ChuTalk/Views/ChatView.swift` (通報UI)

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/data/model/Report.kt
data class Report(
    val reporterId: Int,
    val reportedUserId: Int,
    val messageId: Int?,
    val reason: String,
    val status: String = "pending"
)

enum class ReportReason(val value: String) {
    HARASSMENT("harassment"),
    SPAM("spam"),
    INAPPROPRIATE_CONTENT("inappropriate_content"),
    IMPERSONATION("impersonation"),
    OTHER("other")
}

// app/src/main/java/com/rcclab/chutalk/ui/chat/ReportDialogFragment.kt
class ReportDialogFragment : DialogFragment() {
    // 通報理由選択ダイアログ
    // POST /api/reports
}

// app/src/main/res/layout/dialog_report.xml
- RadioGroup（通報理由選択）
- EditText（詳細説明）
- Button（送信・キャンセル）
```

#### 6. ブロック機能（App Store Guideline 1.2対応）
**iOS版対応ファイル:**
- `ChuTalk/Models/Block.swift`
- `ChuTalk/Views/ChatView.swift` (ブロックUI)

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/data/model/Block.kt
data class Block(
    val blockerId: Int,
    val blockedUserId: Int,
    val createdAt: Long
)

// ChatActivity の Menu に追加
override fun onCreateOptionsMenu(menu: Menu): Boolean {
    menuInflater.inflate(R.menu.chat_menu, menu)
    return true
}

override fun onOptionsItemSelected(item: MenuItem): Boolean {
    return when (item.itemId) {
        R.id.action_block -> {
            showBlockConfirmDialog()
            true
        }
        else -> super.onOptionsItemSelected(item)
    }
}

// API呼び出し
// POST /api/blocks { "blocked_user_id": userId }
// GET /api/blocks (ブロックリスト取得)
// DELETE /api/blocks/{userId} (ブロック解除)
```

#### 7. WebRTC ビデオ通話
**iOS版対応ファイル:**
- `ChuTalk/Services/WebRTCService.swift`
- `ChuTalk/Services/CallManager.swift`
- `ChuTalk/Views/CallView.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/webrtc/WebRTCClient.kt
class WebRTCClient(
    private val context: Context,
    private val peerConnectionObserver: PeerConnectionObserver
) {
    private lateinit var peerConnectionFactory: PeerConnectionFactory
    private var peerConnection: PeerConnection? = null
    private var localVideoTrack: VideoTrack? = null
    private var localAudioTrack: AudioTrack? = null

    fun initializePeerConnectionFactory() { }
    fun createOffer(listener: (SessionDescription) -> Unit) { }
    fun createAnswer(listener: (SessionDescription) -> Unit) { }
    fun setRemoteDescription(sdp: SessionDescription) { }
    fun addIceCandidate(candidate: IceCandidate) { }
}

// app/src/main/java/com/rcclab/chutalk/ui/call/CallActivity.kt
class CallActivity : AppCompatActivity() {
    // SurfaceViewRenderer for local/remote video
    // ミュート・カメラON/OFF・通話終了ボタン
}
```

#### 8. Socket.IO リアルタイム通信
**iOS版対応ファイル:**
- `ChuTalk/Services/SocketService.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/service/SocketService.kt
class SocketService(private val token: String) {
    private var socket: Socket? = null

    fun connect() {
        val opts = IO.Options().apply {
            auth = mapOf("token" to token)
            path = "/signal/socket.io/"
        }
        socket = IO.socket("https://chutalk.ksc-sys.com", opts)

        socket?.on("user-online") { args -> handleUserOnline(args) }
        socket?.on("user-offline") { args -> handleUserOffline(args) }
        socket?.on("offer") { args -> handleOffer(args) }
        socket?.on("answer") { args -> handleAnswer(args) }
        socket?.on("ice") { args -> handleIce(args) }
        socket?.on("message") { args -> handleMessage(args) }
        socket?.on("call-ended") { args -> handleCallEnded(args) }

        socket?.connect()
    }

    fun emit(event: String, data: JSONObject) {
        socket?.emit(event, data)
    }
}
```

#### 9. FCM プッシュ通知（iOS版のVoIP Push相当）
**iOS版対応ファイル:**
- `ChuTalk/Services/VoIPPushService.swift`
- `ChuTalk/AppDelegate.swift`

**Android版実装:**
```kotlin
// app/src/main/java/com/rcclab/chutalk/service/FCMService.kt
class FCMService : FirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        val type = remoteMessage.data["type"]

        when (type) {
            "incoming_call" -> {
                // 着信通知を表示
                // Full-screen intent で CallActivity を起動
                showIncomingCallNotification(remoteMessage.data)
            }
            "new_message" -> {
                // メッセージ通知を表示
                showMessageNotification(remoteMessage.data)
            }
        }
    }

    override fun onNewToken(token: String) {
        // トークンをサーバーに送信
        // POST /api/me/devices { "fcm_token": token }
    }
}

// AndroidManifest.xml
<service
    android:name=".service.FCMService"
    android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
```

## 📦 必要な依存関係（build.gradle.kts）

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services") // Firebase
}

android {
    namespace = "com.rcclab.chutalk"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.rcclab.chutalk"
        minSdk = 23
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    // AndroidX
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.7.0")
    implementation("androidx.lifecycle:lifecycle-livedata-ktx:2.7.0")
    implementation("androidx.fragment:fragment-ktx:1.6.2")
    implementation("androidx.recyclerview:recyclerview:1.3.2")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Networking
    implementation("com.squareup.retrofit2:retrofit:2.9.0")
    implementation("com.squareup.retrofit2:converter-gson:2.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")

    // Socket.IO
    implementation("io.socket:socket.io-client:2.1.0")

    // WebRTC
    implementation("org.webrtc:google-webrtc:1.0.32006")

    // Firebase (Push Notifications)
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")

    // Image Loading
    implementation("io.coil-kt:coil:2.5.0")

    // SharedPreferences (Encrypted)
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // JSON
    implementation("com.google.code.gson:gson:2.10.1")

    // Testing
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}
```

## 🔧 必要な設定ファイル

### 1. Constants.kt
```kotlin
package com.rcclab.chutalk.utils

object Constants {
    // App Store Review Mode (iOS版と同じ概念)
    const val IS_APP_STORE_REVIEW_BUILD = false

    // Server Configuration
    const val BASE_URL = "https://chutalk.ksc-sys.com"
    const val API_URL = "$BASE_URL/api"
    const val SOCKET_URL = BASE_URL
    const val SOCKET_PATH = "/signal/socket.io/"
    const val STUN_SERVER = "stun:chutalk.ksc-sys.com:3478"
    const val TURN_SERVER = "turn:chutalk.ksc-sys.com:3478"

    // API Endpoints
    object API {
        const val REGISTER = "$API_URL/auth/register"
        const val LOGIN = "$API_URL/auth/login"
        const val TURN_CREDENTIALS = "$API_URL/turn-cred"

        val CONTACTS = "$API_URL/contacts${if (IS_APP_STORE_REVIEW_BUILD) ".v2" else ""}"
        val MESSAGES = "$API_URL/messages${if (IS_APP_STORE_REVIEW_BUILD) ".v2" else ""}"

        const val USER_SEARCH = "$API_URL/users/search"
        const val CALLS = "$API_URL/calls"
        const val REPORTS = "$API_URL/reports"
        const val BLOCKS = "$API_URL/blocks"
        const val DEVICES = "$API_URL/me/devices"
    }

    // SharedPreferences Keys
    object Prefs {
        const val AUTH_TOKEN = "auth_token"
        const val USER_ID = "user_id"
        const val USERNAME = "username"
        const val DISPLAY_NAME = "display_name"
        const val HAS_ACCEPTED_TERMS = "has_accepted_terms"
    }

    // Socket Events
    object SocketEvents {
        const val REGISTER = "register"
        const val OFFER = "offer"
        const val ANSWER = "answer"
        const val ICE = "ice"
        const val CALL_END = "call-end"
        const val MESSAGE = "message"

        const val USER_ONLINE = "user-online"
        const val USER_OFFLINE = "user-offline"
        const val INCOMING_OFFER = "offer"
        const val INCOMING_ANSWER = "answer"
        const val INCOMING_ICE = "ice"
        const val CALL_ENDED = "call-ended"
        const val MESSAGE_RECEIVED = "message"
    }
}
```

### 2. AndroidManifest.xml
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <!-- Permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />

    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.ChuTalk"
        android:usesCleartextTraffic="false"
        tools:targetApi="31">

        <!-- Main Activity -->
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Terms of Service Activity -->
        <activity
            android:name=".ui.terms.TermsOfServiceActivity"
            android:exported="false" />

        <!-- Auth Activities -->
        <activity
            android:name=".ui.auth.LoginActivity"
            android:exported="false" />
        <activity
            android:name=".ui.auth.RegisterActivity"
            android:exported="false" />

        <!-- Chat Activity -->
        <activity
            android:name=".ui.chat.ChatActivity"
            android:exported="false"
            android:windowSoftInputMode="adjustResize" />

        <!-- Call Activity -->
        <activity
            android:name=".ui.call.CallActivity"
            android:exported="false"
            android:screenOrientation="portrait"
            android:showWhenLocked="true"
            android:turnScreenOn="true" />

        <!-- FCM Service -->
        <service
            android:name=".service.FCMService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>

        <!-- Socket Service -->
        <service
            android:name=".service.SocketService"
            android:exported="false" />

    </application>

</manifest>
```

### 3. テストアカウント情報
iOS版と同じアカウントを使用：
- **アカウント1:** Username: `rcc122`, Password: `rcc122`
- **アカウント2:** Username: `kohei.t`, Password: `kohei0617`

## 🚀 Claude Code 作業手順

### Phase 1: プロジェクトセットアップ
1. Android Studioで新規プロジェクトを確認
2. `build.gradle.kts`に依存関係を追加
3. `google-services.json`をFirebase Consoleからダウンロードして配置
4. `Constants.kt`を作成
5. `AndroidManifest.xml`を更新

### Phase 2: データレイヤー実装
1. データモデルクラス作成（User, Contact, Message, Report, Block）
2. Retrofit APIインターフェース作成
3. Repositoryパターン実装
4. PreferenceManager作成（SharedPreferences管理）

### Phase 3: UI実装（認証）
1. TermsOfServiceActivity（利用規約）
2. LoginActivity
3. RegisterActivity

### Phase 4: UI実装（メイン機能）
1. MainActivity + NavigationDrawer
2. ContactsFragment（連絡先一覧）
3. ChatActivity（チャット画面）
4. 通報・ブロック機能の統合

### Phase 5: リアルタイム通信
1. SocketService実装
2. FCMService実装（プッシュ通知）

### Phase 6: WebRTC通話機能
1. WebRTCClient実装
2. CallActivity実装
3. PeerConnection管理

### Phase 7: テスト・デバッグ
1. 各機能の動作確認
2. iOS版との互換性確認
3. Google Play審査準備

## 📝 Claude Code への指示例

新しいフォルダでClaude Codeを起動したら、以下のように指示してください：

```
ChuTalk Androidアプリを開発します。

プロジェクト情報：
- プロジェクト名: ChuTalk
- パッケージ名: com.rcclab.chutalk
- 言語: Kotlin
- Minimum SDK: API 23

iOS版の実装仕様書を参照してください：
/Users/rcc/Documents/iosApp/iOS開発/ChuTalk/ChuTalk/ANDROID_DEVELOPMENT_GUIDE.md

Phase 1から順番に実装していきます。
まず、build.gradle.ktsに必要な依存関係を追加してください。
```

その後、Phase 1から順に指示を出してください：
- "Phase 1を実装してください"
- "Phase 2を実装してください"
- など

## 🔗 参考情報

### iOS版ファイルパス
iOS版の実装を参照する場合：
```
/Users/rcc/Documents/iosApp/iOS開発/ChuTalk/ChuTalk/
```

### サーバー情報
- **Base URL:** https://chutalk.ksc-sys.com
- **API Documentation:** サーバー側実装は既に完了
- **データベース:** PostgreSQL (Docker: chutalk_db)

### 重要なAPI仕様
すべてのAPIリクエストには`Authorization: Bearer {token}`ヘッダーが必要です（ログイン・登録を除く）。

---

**作成日:** 2025-10-23
**対象:** Claude Code AI Assistant
**目的:** ChuTalk Android版の効率的な開発
