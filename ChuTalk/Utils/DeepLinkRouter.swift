//
//  DeepLinkRouter.swift
//  ChuTalk
//
//  通知からのディープリンク処理
//

import Foundation
import SwiftUI
import Combine

class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingNavigation: NavigationTarget?

    enum NavigationTarget: Equatable {
        case chat(userId: Int)
        case call(callerId: Int, callUUID: String)
    }

    private init() {}

    func handleNotification(userInfo: [AnyHashable: Any]) {
        print("🔗 DeepLinkRouter: Handling notification")
        print("UserInfo: \(userInfo)")

        guard let type = userInfo["type"] as? String else {
            print("⚠️ DeepLinkRouter: No type in userInfo")
            return
        }

        switch type {
        case "chat.message":
            handleChatMessage(userInfo: userInfo)

        case "call.incoming":
            handleIncomingCall(userInfo: userInfo)

        default:
            print("⚠️ DeepLinkRouter: Unknown type: \(type)")
        }
    }

    private func handleChatMessage(userInfo: [AnyHashable: Any]) {
        guard let fromUserIdString = userInfo["fromUserId"] as? String,
              let fromUserId = Int(fromUserIdString) else {
            print("⚠️ DeepLinkRouter: Invalid fromUserId")
            return
        }

        print("💬 DeepLinkRouter: Navigating to chat with user \(fromUserId)")

        DispatchQueue.main.async {
            self.pendingNavigation = .chat(userId: fromUserId)
        }
    }

    private func handleIncomingCall(userInfo: [AnyHashable: Any]) {
        guard let callerId = userInfo["fromUserId"] as? Int,
              let callUUID = userInfo["callUUID"] as? String else {
            print("⚠️ DeepLinkRouter: Invalid call data")
            return
        }

        print("📞 DeepLinkRouter: Navigating to call with user \(callerId)")

        DispatchQueue.main.async {
            self.pendingNavigation = .call(callerId: callerId, callUUID: callUUID)
        }
    }

    func clearPendingNavigation() {
        pendingNavigation = nil
    }
}
