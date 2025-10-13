//
//  IncomingCallView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI

struct IncomingCallView: View {
    @ObservedObject private var callManager = CallManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Caller info
                VStack(spacing: 24) {
                    if let contact = callManager.currentContact {
                        // Avatar
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 120, height: 120)
                            .overlay(
                                Text(String(contact.displayName.prefix(1)))
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                            )
                            .shadow(radius: 10)

                        // Name
                        Text(contact.displayName)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(.white)

                        Text("@\(contact.username)")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.8))

                        // Call type
                        HStack(spacing: 8) {
                            Image(systemName: callManager.isVideoCall ? "video.fill" : "phone.fill")
                            Text(callManager.isVideoCall ? "ビデオ通話" : "音声通話")
                        }
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(20)

                        Text("着信中...")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.top, 8)
                    }
                }

                Spacer()

                // Call action buttons
                HStack(spacing: 80) {
                    // Reject button
                    VStack(spacing: 12) {
                        Button(action: rejectCall) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 70, height: 70)
                                    .shadow(radius: 10)

                                Image(systemName: "phone.down.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }

                        Text("拒否")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }

                    // Accept button
                    VStack(spacing: 12) {
                        Button(action: acceptCall) {
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 70, height: 70)
                                    .shadow(radius: 10)

                                Image(systemName: "phone.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }

                        Text("応答")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .statusBarHidden()
    }

    private func acceptCall() {
        Task {
            await callManager.acceptIncomingCall()
            dismiss()
        }
    }

    private func rejectCall() {
        Task {
            await callManager.declineIncomingCall()
            dismiss()
        }
    }
}

#Preview {
    IncomingCallView()
}
