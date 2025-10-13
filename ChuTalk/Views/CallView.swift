//
//  CallView.swift
//  ChuTalk
//
//  Created by Claude Code
//

import SwiftUI
import WebRTC

struct CallView: View {
    @ObservedObject private var callManager = CallManager.shared
    @ObservedObject private var webRTCService = WebRTCService.shared
    @ObservedObject private var audioManager = AudioManager.shared

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Video views
                if callManager.isVideoCall && webRTCService.isVideoEnabled {
                    videoViews
                } else {
                    audioOnlyView
                }

                Spacer()

                // Transcription placeholder (for future implementation)
                transcriptionPlaceholder

                // Call controls
                callControls
                    .padding(.bottom, 40)
            }
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            if let contact = callManager.currentContact {
                Text(contact.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }

            // Call type indicator
            HStack(spacing: 6) {
                Image(systemName: callManager.isVideoCall ? "video.fill" : "phone.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                Text(callManager.isVideoCall ? "ビデオ通話" : "音声通話")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(callManager.isVideoCall ? Color.blue.opacity(0.5) : Color.green.opacity(0.5))
            )

            HStack(spacing: 8) {
                statusIndicator

                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.top, 60)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch callManager.callState {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        default:
            return .gray
        }
    }

    private var statusText: String {
        switch callManager.callState {
        case .connected:
            return formatDuration(callManager.callDuration)
        case .connecting:
            return "接続中..."
        case .ringing:
            return "呼び出し中..."
        default:
            return ""
        }
    }

    private var videoViews: some View {
        ZStack(alignment: .topTrailing) {
            // Remote video (full screen)
            if let remoteTrack = webRTCService.getRemoteVideoTrack() {
                VideoView(videoTrack: remoteTrack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("接続を待っています...")
                                .foregroundColor(.white)
                        }
                    )
            }

            // Local video (picture-in-picture)
            if let localTrack = webRTCService.getLocalVideoTrack() {
                VideoView(videoTrack: localTrack)
                    .frame(width: 120, height: 160)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                    .padding(16)
            }
        }
    }

    private var audioOnlyView: some View {
        VStack(spacing: 24) {
            if let contact = callManager.currentContact {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Text(String(contact.displayName.prefix(1)))
                                .font(.system(size: 48))
                                .foregroundColor(.white)
                        )

                    // Phone icon indicator for audio call
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.green)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(width: 120, height: 120)
                }

                Text(contact.displayName)
                    .font(.title)
                    .foregroundColor(.white)

                Text("音声通話")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    private var transcriptionPlaceholder: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.white.opacity(0.6))
                Text("文字起こし")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }

            ScrollView {
                Text("文字起こし機能は開発中です。\n将来のアップデートで利用可能になります。")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .padding(.horizontal)
        .frame(height: 100)
    }

    private var callControls: some View {
        HStack(spacing: 24) {
            // Toggle Video
            if callManager.isVideoCall {
                ControlButton(
                    icon: webRTCService.isVideoEnabled ? "video.fill" : "video.slash.fill",
                    color: webRTCService.isVideoEnabled ? .white : .red,
                    action: {
                        callManager.toggleVideo()
                    }
                )
            }

            // Toggle Audio
            ControlButton(
                icon: webRTCService.isAudioEnabled ? "mic.fill" : "mic.slash.fill",
                color: webRTCService.isAudioEnabled ? .white : .red,
                action: {
                    callManager.toggleMute()
                }
            )

            // End Call
            ControlButton(
                icon: "phone.down.fill",
                color: .white,
                backgroundColor: .red,
                size: 70,
                action: {
                    Task {
                        await callManager.endCall()
                        dismiss()
                    }
                }
            )

            // Toggle Speaker
            ControlButton(
                icon: audioManager.currentDevice == .speaker ? "speaker.wave.3.fill" : "speaker.fill",
                color: .white,
                action: {
                    audioManager.toggleSpeaker()
                }
            )

            // Switch Camera
            if callManager.isVideoCall {
                ControlButton(
                    icon: "camera.rotate.fill",
                    color: .white,
                    action: {
                        callManager.toggleCamera()
                    }
                )
            }
        }
        .padding(.horizontal)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct ControlButton: View {
    let icon: String
    let color: Color
    var backgroundColor: Color = Color.white.opacity(0.2)
    var size: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: size, height: size)

                Image(systemName: icon)
                    .font(.system(size: size * 0.35))
                    .foregroundColor(color)
            }
        }
    }
}

// WebRTC Video View Wrapper
struct VideoView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.contentMode = .scaleAspectFill
        view.videoContentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        videoTrack.add(uiView)
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: ()) {
        // Clean up video track
    }
}

#Preview {
    CallView()
}
