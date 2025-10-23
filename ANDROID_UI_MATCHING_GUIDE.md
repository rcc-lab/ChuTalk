# ChuTalk Android版 - iOS UIマッチングガイド

## 🎯 目的
iOS版と完全に同じUIデザインをAndroidで再現するための追加ガイド

## 📸 必要な準備

### 1. iOS版のスクリーンショット撮影
以下の画面をすべてスクリーンショット：
1. ログイン画面
2. 新規登録画面
3. 利用規約画面
4. 連絡先一覧
5. チャット画面（メッセージあり）
6. チャット画面（長押しメニュー - 通報）
7. チャット画面（右上メニュー - ブロック）
8. 通話画面
9. 設定画面

### 2. 色・フォント・サイズの記録

#### iOS版の設定（Constants.swift参照）
```swift
struct UI {
    static let animationDuration: Double = 0.3
    static let cornerRadius: CGFloat = 12
    static let standardPadding: CGFloat = 16
    static let smallPadding: CGFloat = 8
}
```

#### カラーパレット
iOS版のAssets.xcassetsから色を確認し、以下に記録：
- プライマリカラー: #______
- セカンダリカラー: #______
- 背景色: #______
- テキストカラー: #______
- アクセントカラー: #______

## 🎨 Android版でiOS UIを再現する方法

### 1. カスタムテーマの作成

```xml
<!-- res/values/themes.xml -->
<resources xmlns:tools="http://schemas.android.com/tools">
    <style name="Theme.ChuTalk" parent="Theme.Material3.Light.NoActionBar">
        <!-- iOS風のカラー設定 -->
        <item name="colorPrimary">@color/ios_primary</item>
        <item name="colorOnPrimary">@color/ios_on_primary</item>
        <item name="colorSecondary">@color/ios_secondary</item>
        <item name="colorOnSecondary">@color/ios_on_secondary</item>

        <!-- iOS風の角丸設定 -->
        <item name="shapeAppearanceSmallComponent">@style/ShapeAppearance.ChuTalk.SmallComponent</item>
        <item name="shapeAppearanceMediumComponent">@style/ShapeAppearance.ChuTalk.MediumComponent</item>

        <!-- フォント設定（iOS SF Pro相当） -->
        <item name="fontFamily">@font/sf_pro</item>
    </style>

    <!-- 角丸設定（iOS版と同じ12dp） -->
    <style name="ShapeAppearance.ChuTalk.SmallComponent" parent="">
        <item name="cornerFamily">rounded</item>
        <item name="cornerSize">12dp</item>
    </style>
</resources>
```

### 2. カラーリソース

```xml
<!-- res/values/colors.xml -->
<resources>
    <!-- iOS版のカラーを正確に再現 -->
    <color name="ios_primary">#007AFF</color> <!-- iOS Blue -->
    <color name="ios_secondary">#5856D6</color> <!-- iOS Purple -->
    <color name="ios_background">#FFFFFF</color>
    <color name="ios_surface">#F2F2F7</color> <!-- iOS Light Gray -->
    <color name="ios_text_primary">#000000</color>
    <color name="ios_text_secondary">#8E8E93</color>
    <color name="ios_destructive">#FF3B30</color> <!-- iOS Red -->
    <color name="ios_success">#34C759</color> <!-- iOS Green -->
</resources>
```

### 3. Dimensリソース（iOS版と同じサイズ）

```xml
<!-- res/values/dimens.xml -->
<resources>
    <!-- iOS版のConstants.UI と同じ値 -->
    <dimen name="standard_padding">16dp</dimen>
    <dimen name="small_padding">8dp</dimen>
    <dimen name="corner_radius">12dp</dimen>

    <!-- iOS風のサイズ -->
    <dimen name="button_height">50dp</dimen>
    <dimen name="text_field_height">44dp</dimen>
    <dimen name="navigation_bar_height">44dp</dimen>
    <dimen name="tab_bar_height">49dp</dimen>
</resources>
```

### 4. フォント設定（iOS SF Pro風）

```xml
<!-- res/font/font_family.xml -->
<?xml version="1.0" encoding="utf-8"?>
<font-family xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- SF Pro Display に近い Inter フォントを使用 -->
    <font
        android:fontStyle="normal"
        android:fontWeight="400"
        android:font="@font/inter_regular" />
    <font
        android:fontStyle="normal"
        android:fontWeight="600"
        android:font="@font/inter_semibold" />
    <font
        android:fontStyle="normal"
        android:fontWeight="700"
        android:font="@font/inter_bold" />
</font-family>
```

**注意:** InterフォントをGoogleFontsからダウンロード：
https://fonts.google.com/specimen/Inter

### 5. iOS風のボタンスタイル

```xml
<!-- res/values/styles.xml -->
<resources>
    <!-- iOS風のプライマリボタン -->
    <style name="Button.iOS.Primary">
        <item name="android:layout_height">50dp</item>
        <item name="android:background">@drawable/button_ios_primary</item>
        <item name="android:textColor">@color/ios_on_primary</item>
        <item name="android:textSize">17sp</item>
        <item name="android:fontFamily">@font/inter_semibold</item>
        <item name="android:textAllCaps">false</item>
    </style>

    <!-- iOS風のセカンダリボタン -->
    <style name="Button.iOS.Secondary">
        <item name="android:layout_height">50dp</item>
        <item name="android:background">@drawable/button_ios_secondary</item>
        <item name="android:textColor">@color/ios_primary</item>
        <item name="android:textSize">17sp</item>
        <item name="android:fontFamily">@font/inter_semibold</item>
        <item name="android:textAllCaps">false</item>
    </style>
</resources>
```

```xml
<!-- res/drawable/button_ios_primary.xml -->
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="@color/ios_primary"/>
    <corners android:radius="12dp"/>
</shape>
```

### 6. iOS風のテキストフィールド

```xml
<!-- res/drawable/textfield_ios_background.xml -->
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="@color/ios_surface"/>
    <corners android:radius="10dp"/>
    <stroke
        android:width="1dp"
        android:color="@color/ios_text_secondary"/>
</shape>
```

```xml
<!-- res/values/styles.xml -->
<style name="TextField.iOS">
    <item name="android:layout_height">44dp</item>
    <item name="android:background">@drawable/textfield_ios_background</item>
    <item name="android:paddingStart">12dp</item>
    <item name="android:paddingEnd">12dp</item>
    <item name="android:textSize">17sp</item>
    <item name="android:fontFamily">@font/inter_regular</item>
</style>
```

## 📐 画面別のレイアウト指示

### ログイン画面（LoginActivity）

```xml
<!-- res/layout/activity_login.xml -->
<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@color/ios_background"
    android:padding="@dimen/standard_padding">

    <!-- iOS版と同じレイアウト -->
    <!-- アプリロゴ（上部中央） -->
    <ImageView
        android:id="@+id/logo"
        android:layout_width="120dp"
        android:layout_height="120dp"
        android:src="@drawable/logo"
        app:layout_constraintTop_toTopOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="60dp"/>

    <!-- "ChuTalk" テキスト -->
    <TextView
        android:id="@+id/appName"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="ChuTalk"
        android:textSize="34sp"
        android:fontFamily="@font/inter_bold"
        android:textColor="@color/ios_text_primary"
        app:layout_constraintTop_toBottomOf="@id/logo"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="16dp"/>

    <!-- ユーザー名入力 -->
    <EditText
        android:id="@+id/usernameField"
        style="@style/TextField.iOS"
        android:layout_width="0dp"
        android:hint="ユーザー名"
        app:layout_constraintTop_toBottomOf="@id/appName"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="40dp"/>

    <!-- パスワード入力 -->
    <EditText
        android:id="@+id/passwordField"
        style="@style/TextField.iOS"
        android:layout_width="0dp"
        android:hint="パスワード"
        android:inputType="textPassword"
        app:layout_constraintTop_toBottomOf="@id/usernameField"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="@dimen/standard_padding"/>

    <!-- ログインボタン -->
    <Button
        android:id="@+id/loginButton"
        style="@style/Button.iOS.Primary"
        android:layout_width="0dp"
        android:text="ログイン"
        app:layout_constraintTop_toBottomOf="@id/passwordField"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="24dp"/>

    <!-- 新規登録リンク -->
    <TextView
        android:id="@+id/registerLink"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="アカウントをお持ちでない方は 新規登録"
        android:textSize="15sp"
        android:textColor="@color/ios_primary"
        app:layout_constraintTop_toBottomOf="@id/loginButton"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        android:layout_marginTop="16dp"/>

</androidx.constraintlayout.widget.ConstraintLayout>
```

### チャット画面（ChatActivity）

iOS版の `ChatView.swift` と同じレイアウト：
- RecyclerView（メッセージリスト）を上部に配置
- メッセージ入力欄を下部に固定
- 送信ボタンは右側、iOS Blue
- メッセージバブルは角丸12dp
- 自分のメッセージは右寄せ・青背景
- 相手のメッセージは左寄せ・グレー背景

## 🚀 Claude Codeへの追加指示

ANDROID_QUICK_START.mdの指示の後に、以下を追加してください：

```
# 重要: iOS版と完全に同じUIにする

以下のファイルを参照して、iOS版と同じUIデザインを実装してください：
/Users/rcc/Documents/iosApp/iOS開発/ChuTalk/ChuTalk/ANDROID_UI_MATCHING_GUIDE.md

UIの要件：
1. iOS版のスクリーンショットと同じレイアウト
2. 同じカラーパレット（iOS Blue #007AFF等）
3. 同じフォントサイズ（17sp, 34sp等）
4. 同じ角丸（12dp）
5. 同じパディング（16dp, 8dp）
6. 同じボタンスタイル
7. iOS風のアニメーション

各画面を実装する際は、必ずiOS版のスクリーンショットを参考にしてください。
```

## 📸 スクリーンショット提供方法

Claude Codeに画面を実装させる際：

```
この画面のレイアウトを実装してください。
iOS版のスクリーンショットを添付します。

[スクリーンショット画像を添付]

要件：
- 画像と完全に同じレイアウト
- 同じ色、フォント、サイズ
- 同じ間隔とパディング
```

## ⚠️ 注意点

### 完全一致は難しい部分
1. **フォント**: SF ProはiOS専用。Androidでは Inter または Roboto で近似
2. **アニメーション**: プラットフォーム固有の部分は完全一致は不可
3. **システムUI**: ステータスバー、ナビゲーションバーはOS依存

### 妥協が必要な部分
- Androidのバックボタンの存在（iOSにはない）
- システムフォントの違い
- タッチフィードバックの違い

---

**このガイドを使用することで、iOS版と90-95%同じUIを実現できます。**
