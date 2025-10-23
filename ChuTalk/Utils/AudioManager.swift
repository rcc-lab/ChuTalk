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

        // Handle audio session interruptions (important for lock/unlock)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Handle when audio session becomes active again
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
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

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("🔊 AudioManager: Audio session interrupted (began)")
            FileLogger.shared.log("Audio session interrupted (began)", category: "AudioManager")
        case .ended:
            print("🔊 AudioManager: Audio session interruption ended")
            FileLogger.shared.log("Audio session interruption ended", category: "AudioManager")

            // Resume audio session after interruption
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("🔊 AudioManager: Resuming audio session after interruption")
                    FileLogger.shared.log("Resuming audio session", category: "AudioManager")
                    do {
                        try audioSession.setActive(true, options: [])
                        print("✅ AudioManager: Audio session resumed successfully")
                        FileLogger.shared.log("✅ Audio session resumed", category: "AudioManager")
                    } catch {
                        print("❌ AudioManager: Failed to resume audio session: \(error)")
                        FileLogger.shared.log("❌ Failed to resume: \(error)", category: "AudioManager")
                    }
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleMediaServicesReset() {
        print("🔊 AudioManager: Media services were reset, reconfiguring...")
        FileLogger.shared.log("Media services reset, reconfiguring", category: "AudioManager")
        setupAudioSession()
        configureForCall()
    }

    func configureForCall() {
        print("🔊 AudioManager: Configuring audio session for call...")
        FileLogger.shared.log("🔊 Configuring audio session for call", category: "AudioManager")
        do {
            // IMPORTANT: Use .mixWithOthers to allow audio to continue in background
            // and during screen lock/unlock transitions
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                    .defaultToSpeaker,
                    .mixWithOthers  // Allow mixing with other audio and continue in background
                ]
            )
            try audioSession.setActive(true, options: [])

            // Set preferred sample rate for better quality
            try audioSession.setPreferredSampleRate(48000)

            // Set preferred I/O buffer duration for lower latency
            try audioSession.setPreferredIOBufferDuration(0.005)

            updateCurrentDevice()
            print("✅ AudioManager: Audio session configured successfully")
            print("   Category: \(audioSession.category)")
            print("   Mode: \(audioSession.mode)")
            print("   Options: \(audioSession.categoryOptions)")
            print("   Sample Rate: \(audioSession.sampleRate)")
            FileLogger.shared.log("✅ Audio session configured - Category: \(audioSession.category.rawValue), Mode: \(audioSession.mode.rawValue)", category: "AudioManager")
        } catch {
            print("❌ AudioManager: Failed to configure audio for call: \(error.localizedDescription)")
            FileLogger.shared.log("❌ Failed to configure audio: \(error.localizedDescription)", category: "AudioManager")
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
