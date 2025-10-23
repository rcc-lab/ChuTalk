//
//  AppDelegate.swift
//  ChuTalk
//
//  アプリケーションライフサイクルとプッシュ通知の管理
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("✅ AppDelegate: didFinishLaunchingWithOptions")

        // CallKitの初期化（着信処理に必須）
        _ = CallKitProvider.shared

        // VoIP PushKitの登録
        print("📱 AppDelegate: Registering for VoIP pushes...")
        print("📱 AppDelegate: Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        VoIPPushService.shared.registerForVoIPPushes()

        // 通知権限のチェックとリクエスト
        Task {
            await NotificationsService.shared.checkAuthorizationStatus()

            // 自動的に通知許諾をリクエスト（初回のみ）
            if NotificationsService.shared.authorizationStatus == .notDetermined {
                print("📱 AppDelegate: Requesting notification permission...")
                let granted = await NotificationsService.shared.requestAuthorization()
                if granted {
                    print("✅ AppDelegate: Notification permission granted")
                } else {
                    print("❌ AppDelegate: Notification permission denied")
                }
            } else if NotificationsService.shared.authorizationStatus == .authorized {
                // 既に許可されている場合も明示的に登録
                print("✅ AppDelegate: Notification already authorized, registering for remote notifications...")
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        return true
    }

    // APNsトークン登録成功
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("✅ AppDelegate: didRegisterForRemoteNotificationsWithDeviceToken")
        NotificationsService.shared.registerAPNsToken(deviceToken)
    }

    // APNsトークン登録失敗
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ AppDelegate: didFailToRegisterForRemoteNotificationsWithError - \(error)")
    }

    // バックグラウンドでのリモート通知受信
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📨 AppDelegate: ========== REMOTE NOTIFICATION ==========")
        print("📨 AppDelegate: Application state: \(application.applicationState.rawValue)")
        print("📨 AppDelegate: UserInfo: \(userInfo)")

        // Parse notification type
        if let type = userInfo["type"] as? String {
            print("📨 AppDelegate: Notification type: \(type)")
        }
        if let aps = userInfo["aps"] as? [String: Any] {
            print("📨 AppDelegate: APS: \(aps)")
        }

        // アプリが起動中(Active)の場合のみディープリンク処理を実行
        // Background/Inactiveの場合は通知タップ時に処理される
        if application.applicationState == .active {
            print("📨 AppDelegate: App is active, handling notification immediately")
            DeepLinkRouter.shared.handleNotification(userInfo: userInfo)
        } else {
            print("📨 AppDelegate: App is background/inactive, notification will be handled on tap")
        }

        completionHandler(.newData)
    }
}
