//
//  ContentView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var messagingService = MessagingService.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @EnvironmentObject private var deepLinkRouter: DeepLinkRouter

    @State private var showNotificationBanner = false
    @State private var notificationMessage = ""
    @State private var selectedTab = 0
    @State private var navigationToChatUserId: Int?

    var body: some View {
        ZStack {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .fullScreenCover(isPresented: $callManager.showActiveCallView) {
                            CallView()
                        }
                        .onAppear {
                            startServices()
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .newMessageReceived)) { notification in
                            handleNewMessage(notification)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .acceptIncomingCall)) { notification in
                            handleAcceptCall(notification)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .callKitAnswerCall)) { notification in
                            handleCallKitAnswer(notification)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .callKitEndCall)) { notification in
                            handleCallKitEnd(notification)
                        }
                        .onChange(of: deepLinkRouter.pendingNavigation) { newValue in
                            handleDeepLink(newValue)
                        }
                } else {
                    LoginView()
                }
            }

            // メッセージ通知バナー（上部）
            if showNotificationBanner || notificationService.hasNewMessage {
                VStack {
                    HStack {
                        Image(systemName: notificationService.hasNewMessage ? "message.fill" : "bell.fill")
                            .foregroundColor(.white)

                        if notificationService.hasNewMessage {
                            VStack(alignment: .leading) {
                                Text(notificationService.newMessageFrom ?? "")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(notificationService.messageBody ?? "")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                            }
                        } else {
                            Text(notificationMessage)
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding()
                    .shadow(radius: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
                }
                .zIndex(1)
                .onAppear {
                    if showNotificationBanner {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation {
                                showNotificationBanner = false
                            }
                        }
                    }
                }
            }

            // 着信はCallKitで処理するため、カスタム着信画面は不要
            // CallKitが自動的に着信UIを表示します
        }
        .task {
            // Try auto-login on launch
            if !authService.isAuthenticated {
                _ = await authService.autoLogin()
            }

            // Request notification permission if authenticated
            if authService.isAuthenticated {
                await NotificationsService.shared.checkAuthorizationStatus()
                if NotificationsService.shared.authorizationStatus == .notDetermined {
                    print("📱 ContentView: Requesting notification permission...")
                    _ = await NotificationsService.shared.requestAuthorization()
                }
            }
        }
    }

    private func startServices() {
        guard let userId = authService.currentUser?.id else { return }

        print("👤 ContentView: 現在のユーザーID: \(userId)")
        print("🔍 ContentView: 着信監視を開始します")

        // NotificationServiceで着信とメッセージを監視
        notificationService.startMonitoring(userId: userId)
        print("✅ ContentView: Started NotificationService monitoring for user \(userId)")
    }

    private func handleNewMessage(_ notification: Notification) {
        guard let userId = notification.userInfo?["userId"] as? Int else { return }

        Task {
            if let contact = try? await ContactsService.shared.getContact(byId: userId) {
                await MainActor.run {
                    notificationMessage = "\(contact.displayName)から新着メッセージ"
                    withAnimation {
                        showNotificationBanner = true
                    }
                }
            }
        }
    }

    private func handleAcceptCall(_ notification: Notification) {
        guard let callerId = notification.userInfo?["callerId"] as? Int,
              let offer = notification.userInfo?["offer"] as? String,
              let callerName = notification.userInfo?["callerName"] as? String else { return }

        print("✅ ContentView: Accepting call from \(callerName) (ID: \(callerId))")

        Task {
            if let contact = try? await ContactsService.shared.getContact(byId: callerId),
               let userId = authService.currentUser?.id {
                // 正しい形式: "発信者ID-着信者ID"
                let callId = "\(callerId)-\(userId)"

                print("✅ ContentView: Using callId: \(callId)")

                await MainActor.run {
                    // CallManagerに着信情報を設定
                    callManager.incomingCallerId = callerId
                    callManager.incomingOffer = offer
                    callManager.currentContact = contact
                    callManager.callId = callId
                }

                // 着信応答を実行
                await callManager.acceptIncomingCall()
            }
        }
    }

    private func handleCallKitAnswer(_ notification: Notification) {
        print("📞 ContentView: ========== CALLKIT ANSWER ==========")
        print("✅ ContentView: CallManager handles all CallKit answer logic")
        print("   (ContentView delegates to CallManager to avoid duplicate processing)")

        // CallManagerが全ての処理を行うため、ContentView側では何もしない
        // これにより二重処理を防ぎ、以下の問題を解決：
        // 1. acceptIncomingCall()が2回呼ばれる問題
        // 2. hasVideo情報の競合
        // 3. 1回目の通話接続失敗
    }

    private func handleCallKitEnd(_ notification: Notification) {
        print("📞 ContentView: CallKit end call")

        Task { @MainActor in
            // CallManagerのendCallがすべての処理を行う
            await callManager.endCall()

            // NotificationServiceの着信状態をクリア
            notificationService.hasIncomingCall = false
            notificationService.incomingCallerId = nil
            notificationService.incomingOffer = nil
        }
    }

    private func handleDeepLink(_ navigation: DeepLinkRouter.NavigationTarget?) {
        guard let navigation = navigation else { return }

        switch navigation {
        case .chat(let userId):
            print("💬 ContentView: Deep link to chat with user \(userId)")
            navigationToChatUserId = userId
            selectedTab = 0 // 連絡先タブに移動

        case .call(let callerId, let callUUID):
            print("📞 ContentView: Deep link to call with user \(callerId)")
            // CallKitが既に処理しているので、ここでは何もしない
        }

        deepLinkRouter.clearPendingNavigation()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let incomingCallDetected = Notification.Name("incomingCallDetected")
}

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ContactsListView()
                .tabItem {
                    Label("連絡先", systemImage: "person.2.fill")
                }
                .tag(0)

            CallHistoryView()
                .tabItem {
                    Label("履歴", systemImage: "clock.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    ContentView()
}
