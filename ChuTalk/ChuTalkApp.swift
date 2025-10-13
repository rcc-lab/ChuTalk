//
//  ChuTalkApp.swift
//  ChuTalk
//
//  Created by RCC on 2025/10/07.
//

import SwiftUI

@main
struct ChuTalkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deepLinkRouter)
        }
    }
}
