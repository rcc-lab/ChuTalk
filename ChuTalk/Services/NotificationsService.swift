//
//  NotificationsService.swift
//  ChuTalk
//
//  APNs通知の登録とハンドリング
//

import Foundation
import Combine
import UserNotifications
import UIKit

class NotificationsService: NSObject, ObservableObject {
    static let shared = NotificationsService()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var apnsDeviceToken: String?
    private var retryCount = 0
    private let maxRetries = 3

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])

            await MainActor.run {
                self.authorizationStatus = granted ? .authorized : .denied
            }

            if granted {
                print("✅ NotificationsService: Notification permission granted")
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("❌ NotificationsService: Notification permission denied")
            }

            return granted
        } catch {
            print("❌ NotificationsService: Authorization error - \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            print("📱 NotificationsService: Authorization status: \(settings.authorizationStatus.rawValue)")
            print("   Alert: \(settings.alertSetting.rawValue)")
            print("   Badge: \(settings.badgeSetting.rawValue)")
            print("   Sound: \(settings.soundSetting.rawValue)")
        }
    }

    // MARK: - Device Token Registration

    func registerAPNsToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        self.apnsDeviceToken = tokenString

        print("✅ NotificationsService: APNs token: \(tokenString)")

        // サーバーに登録
        Task {
            await uploadDeviceToken(apnsToken: tokenString, voipToken: nil)
        }
    }

    func registerVoIPToken(_ token: String) {
        print("✅ NotificationsService: VoIP token: \(token)")

        // サーバーに登録
        Task {
            await uploadDeviceToken(apnsToken: apnsDeviceToken, voipToken: token)
        }
    }

    // ログイン後に保存されているトークンを再アップロード
    func reuploadSavedTokens() {
        print("📤 NotificationsService: Reuploading saved tokens after login...")

        Task {
            // VoIPトークンを取得
            let voipToken = VoIPPushService.shared.voipDeviceToken

            // 両方のトークンが揃っていればアップロード
            if apnsDeviceToken != nil || voipToken != nil {
                await uploadDeviceToken(apnsToken: apnsDeviceToken, voipToken: voipToken)
            } else {
                print("⚠️ NotificationsService: No tokens to reupload")
            }
        }
    }

    private func uploadDeviceToken(apnsToken: String?, voipToken: String?) async {
        guard let url = URL(string: Constants.API.devices),
              let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) else {
            print("❌ NotificationsService: Missing auth token or URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "platform": "ios",
            "bundleId": Bundle.main.bundleIdentifier ?? "rcc.takaokanet.com.ChuTalk"
        ]
        if let apnsToken = apnsToken {
            body["apnsDeviceToken"] = apnsToken
        }
        if let voipToken = voipToken {
            body["voipDeviceToken"] = voipToken
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "NotificationsService", code: -1)
            }

            if httpResponse.statusCode == 200 {
                print("✅ NotificationsService: Device tokens uploaded successfully")
                retryCount = 0
            } else {
                print("❌ NotificationsService: Upload failed with status \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }

                // リトライ
                await retryUpload(apnsToken: apnsToken, voipToken: voipToken)
            }
        } catch {
            print("❌ NotificationsService: Upload error - \(error)")
            await retryUpload(apnsToken: apnsToken, voipToken: voipToken)
        }
    }

    private func retryUpload(apnsToken: String?, voipToken: String?) async {
        guard retryCount < maxRetries else {
            print("❌ NotificationsService: Max retries reached")
            return
        }

        retryCount += 1
        let delay = pow(2.0, Double(retryCount)) // Exponential backoff
        print("⚠️ NotificationsService: Retrying in \(delay) seconds (attempt \(retryCount)/\(maxRetries))")

        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await uploadDeviceToken(apnsToken: apnsToken, voipToken: voipToken)
    }

    // MARK: - Local Notifications (for testing)

    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "テスト通知"
        content.body = "これはテストメッセージです"
        content.sound = .default
        content.userInfo = [
            "type": "chat.message",
            "convId": "test",
            "fromUserId": "999"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ NotificationsService: Test notification error - \(error)")
            } else {
                print("✅ NotificationsService: Test notification scheduled")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationsService: UNUserNotificationCenterDelegate {
    // フォアグラウンド表示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📨 NotificationsService: ========== FOREGROUND NOTIFICATION ==========")
        print("📨 NotificationsService: Title: \(notification.request.content.title)")
        print("📨 NotificationsService: Body: \(notification.request.content.body)")
        print("📨 NotificationsService: Sound: \(notification.request.content.sound?.description ?? "none")")
        print("📨 NotificationsService: Badge: \(notification.request.content.badge ?? 0)")
        print("📨 NotificationsService: UserInfo: \(notification.request.content.userInfo)")

        // iOS 14+ でバナーとサウンドを表示
        completionHandler([.banner, .sound, .badge])
    }

    // 通知タップ
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📨 NotificationsService: ========== NOTIFICATION TAPPED ==========")
        print("📨 NotificationsService: Action: \(response.actionIdentifier)")
        let userInfo = response.notification.request.content.userInfo
        print("📨 NotificationsService: UserInfo: \(userInfo)")

        // Parse notification type
        if let type = userInfo["type"] as? String {
            print("📨 NotificationsService: Type: \(type)")
        }

        // ディープリンク処理
        DeepLinkRouter.shared.handleNotification(userInfo: userInfo)

        completionHandler()
    }
}
