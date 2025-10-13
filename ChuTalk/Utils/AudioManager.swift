//
//  AudioManager.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import AVFoundation
import AudioToolbox

enum AudioDevice {
    case speaker
    case receiver
    case bluetooth
    case headphones
}

class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var currentDevice: AudioDevice = .receiver
    @Published var isMuted: Bool = false

    private let audioSession = AVAudioSession.sharedInstance()
    private var ringtonePlayer: AVAudioPlayer?
    private var ringtoneTimer: Timer?

    private init() {
        setupAudioSession()
        registerForNotifications()
    }

    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
        }
    }

    private func registerForNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            updateCurrentDevice()
        default:
            break
        }
    }

    func configureForCall() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try audioSession.setActive(true)
            updateCurrentDevice()
        } catch {
            print("Failed to configure audio for call: \(error.localizedDescription)")
        }
    }

    func configureForEndCall() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    func toggleSpeaker() {
        let shouldUseSpeaker = currentDevice != .speaker

        do {
            if shouldUseSpeaker {
                try audioSession.overrideOutputAudioPort(.speaker)
                currentDevice = .speaker
            } else {
                try audioSession.overrideOutputAudioPort(.none)
                updateCurrentDevice()
            }
        } catch {
            print("Failed to toggle speaker: \(error.localizedDescription)")
        }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        // Note: Actual muting should be done in WebRTC audio track
        // This is just for UI state management
    }

    private func updateCurrentDevice() {
        let currentRoute = audioSession.currentRoute

        if let output = currentRoute.outputs.first {
            switch output.portType {
            case .builtInSpeaker:
                currentDevice = .speaker
            case .builtInReceiver:
                currentDevice = .receiver
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                currentDevice = .bluetooth
            case .headphones, .headsetMic:
                currentDevice = .headphones
            default:
                currentDevice = .receiver
            }
        }
    }

    func getAvailableAudioDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = [.receiver, .speaker]

        let currentRoute = audioSession.currentRoute
        for input in currentRoute.inputs {
            switch input.portType {
            case .bluetoothHFP:
                if !devices.contains(.bluetooth) {
                    devices.append(.bluetooth)
                }
            case .headsetMic:
                if !devices.contains(.headphones) {
                    devices.append(.headphones)
                }
            default:
                break
            }
        }

        return devices
    }

    // MARK: - Ringtone

    func playRingtone() {
        // Stop any existing ringtone
        stopRingtone()

        do {
            // Configure audio session for ringtone playback
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)

            // Use system ringtone file
            guard let soundURL = Bundle.main.url(forResource: "ringtone", withExtension: "caf") ??
                                 URL(string: "/System/Library/Audio/UISounds/Ringtone.caf") else {
                print("⚠️ AudioManager: Ringtone file not found, using system sound")
                // Fallback: Play system sound in a loop
                playSystemRingtone()
                return
            }

            ringtonePlayer = try AVAudioPlayer(contentsOf: soundURL)
            ringtonePlayer?.numberOfLoops = -1 // Loop indefinitely
            ringtonePlayer?.volume = 1.0
            ringtonePlayer?.prepareToPlay()
            ringtonePlayer?.play()

            // Also vibrate
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

            print("✅ AudioManager: Playing ringtone (looping)")
        } catch {
            print("❌ AudioManager: Failed to play ringtone - \(error), using fallback")
            playSystemRingtone()
        }
    }

    private func playSystemRingtone() {
        // Fallback: repeatedly play system sound
        var playCount = 0
        ringtoneTimer?.invalidate()
        ringtoneTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self, playCount < 10 else {
                timer.invalidate()
                self?.ringtoneTimer = nil
                return
            }
            AudioServicesPlaySystemSound(SystemSoundID(1005))
            if playCount % 2 == 0 {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
            playCount += 1
        }
    }

    func stopRingtone() {
        ringtonePlayer?.stop()
        ringtonePlayer = nil
        ringtoneTimer?.invalidate()
        ringtoneTimer = nil
        print("✅ AudioManager: Stopped ringtone")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
