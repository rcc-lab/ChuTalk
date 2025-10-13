//
//  IncomingCallScreen.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct IncomingCallScreen: View {
    @ObservedObject private var notificationService = NotificationService.shared

    var body: some View {
        ZStack {
            // 背景をぼかす
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Text("着信")
                    .font(.largeTitle)
                    .foregroundColor(.white)

                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.white)

                Text(notificationService.incomingCallerName ?? "不明")
                    .font(.title)
                    .foregroundColor(.white)

                Spacer()
                    .frame(height: 100)

                HStack(spacing: 80) {
                    // 拒否ボタン
                    Button(action: {
                        notificationService.declineCall()
                    }) {
                        VStack {
                            Image(systemName: "phone.down.circle.fill")
                                .resizable()
                                .frame(width: 70, height: 70)
                                .foregroundColor(.red)
                            Text("拒否")
                                .foregroundColor(.white)
                        }
                    }

                    // 応答ボタン
                    Button(action: {
                        notificationService.acceptCall()
                    }) {
                        VStack {
                            Image(systemName: "phone.circle.fill")
                                .resizable()
                                .frame(width: 70, height: 70)
                                .foregroundColor(.green)
                            Text("応答")
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.bottom, 60)
            }
        }
    }
}

struct MessageNotificationBanner: View {
    let from: String
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "message.fill")
                .foregroundColor(.white)

            VStack(alignment: .leading) {
                Text(from)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue)
        .cornerRadius(15)
        .padding(.horizontal)
        .padding(.top, 50)
        .shadow(radius: 10)
    }
}
