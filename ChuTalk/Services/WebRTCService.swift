//
//  WebRTCService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import WebRTC
import AVFoundation

class WebRTCService: NSObject, ObservableObject {
    static let shared = WebRTCService()

    private var peerConnection: RTCPeerConnection?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localVideoSource: RTCVideoSource?
    private var videoFrameCount: Int = 0
    private var lastFrameTime: Date?
    private var callKitAudioSessionActivated: Bool = false
    private var cameraStartPending: Bool = false
    private var disconnectTimer: Timer?
    private var lastIceState: RTCIceConnectionState = .new

    @Published var localVideoView: RTCVideoRenderer?
    @Published var remoteVideoView: RTCVideoRenderer?
    @Published var isVideoEnabled = true
    @Published var isAudioEnabled = true

    var onIceCandidate: ((RTCIceCandidate) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onRemoteStreamAdded: (() -> Void)?

    var isReadyForCandidates: Bool {
        return peerConnection != nil && peerConnection?.remoteDescription != nil
    }

    private override init() {
        super.init()
        setupPeerConnectionFactory()
        setupNotifications()
    }

    private func setupNotifications() {
        // Listen for CallKit audio session activation
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCallKitAudioSessionActivated),
            name: .callKitAudioSessionActivated,
            object: nil
        )
    }

    @objc private func handleCallKitAudioSessionActivated() {
        print("🎙️ WebRTCService: CallKit audio session activated")
        print("🔍 WebRTCService: Current state - cameraStartPending: \(cameraStartPending), videoCapturer: \(videoCapturer != nil)")
        FileLogger.shared.log("🎙️ CallKit audio session activated - pending: \(cameraStartPending), capturer: \(videoCapturer != nil)", category: "WebRTCService")

        // Mark that CallKit audio session is now active
        callKitAudioSessionActivated = true

        // If camera start is pending and videoCapturer is ready, start camera now
        if cameraStartPending {
            if videoCapturer != nil {
                print("▶️ WebRTCService: Starting camera (pending start + capturer ready)")
                FileLogger.shared.log("▶️ Starting camera (pending start + capturer ready)", category: "WebRTCService")
                cameraStartPending = false
                startCaptureLocalVideo()
            } else {
                print("⏸️ WebRTCService: Camera start pending, but capturer not ready yet - will start when capturer is created")
                FileLogger.shared.log("⏸️ Camera start pending, capturer not ready - will retry", category: "WebRTCService")
                // Keep cameraStartPending = true, it will be checked again in setupLocalTracks
            }
        } else {
            print("ℹ️ WebRTCService: No camera start pending")
            FileLogger.shared.log("ℹ️ No camera start pending", category: "WebRTCService")
        }
    }

    private func setupPeerConnectionFactory() {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }

    func setupPeerConnection(with iceServers: [RTCIceServer], isVideo: Bool = true) {
        print("🔧 WebRTCService: Setting up peer connection")
        print("   ICE servers: \(iceServers.count)")
        print("   Video enabled: \(isVideo)")
        FileLogger.shared.log("🔧 Setting up peer connection - ICE servers: \(iceServers.count), isVideo: \(isVideo)", category: "WebRTCService")

        // IMPORTANT: Clean up any existing peer connection first
        if peerConnection != nil {
            print("⚠️ WebRTCService: Existing peer connection found, cleaning up first")
            FileLogger.shared.log("⚠️ Existing peer connection found, cleaning up first", category: "WebRTCService")

            // Save CallKit flags before close (to preserve state for quick successive calls)
            let savedCallKitActivated = callKitAudioSessionActivated
            let savedCameraPending = cameraStartPending

            close()

            // Restore CallKit flags (CallKit session may still be active)
            callKitAudioSessionActivated = savedCallKitActivated
            cameraStartPending = savedCameraPending
            print("🔧 WebRTCService: Preserved CallKit state - activated: \(savedCallKitActivated), pending: \(savedCameraPending)")
            FileLogger.shared.log("🔧 Preserved CallKit state - activated: \(savedCallKitActivated), pending: \(savedCameraPending)", category: "WebRTCService")
        }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        peerConnection = peerConnectionFactory?.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        if peerConnection == nil {
            print("❌ WebRTCService: Failed to create peer connection")
            FileLogger.shared.log("❌ Failed to create peer connection", category: "WebRTCService")
            return
        }

        print("✅ WebRTCService: Peer connection created")
        FileLogger.shared.log("✅ Peer connection created successfully", category: "WebRTCService")
        setupLocalTracks(isVideo: isVideo)
    }

    private func setupLocalTracks(isVideo: Bool) {
        print("🎥 WebRTCService: Setting up local tracks - isVideo: \(isVideo)")
        FileLogger.shared.log("🎥 Setting up local tracks - isVideo: \(isVideo)", category: "WebRTCService")

        // Audio track (always setup FIRST - this is standard practice)
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory?.audioSource(with: audioConstraints)
        localAudioTrack = peerConnectionFactory?.audioTrack(with: audioSource!, trackId: "audio0")
        localAudioTrack?.isEnabled = isAudioEnabled

        // Add audio track
        if let audioTrack = localAudioTrack {
            peerConnection?.add(audioTrack, streamIds: ["stream0"])
            print("✅ WebRTCService: Audio track added")
            FileLogger.shared.log("✅ Audio track added", category: "WebRTCService")
        } else {
            print("❌ WebRTCService: Failed to create audio track")
            FileLogger.shared.log("❌ Failed to create audio track", category: "WebRTCService")
        }

        // Video track (setup AFTER audio)
        if isVideo {
            print("🎥 WebRTCService: Creating video track...")
            FileLogger.shared.log("🎥 Creating video track", category: "WebRTCService")

            localVideoSource = peerConnectionFactory?.videoSource()

            #if !targetEnvironment(simulator)
            // Reset frame counter for new call
            videoFrameCount = 0
            lastFrameTime = nil

            videoCapturer = RTCCameraVideoCapturer(delegate: localVideoSource!)
            print("✅ WebRTCService: Video capturer created")
            FileLogger.shared.log("✅ Video capturer created", category: "WebRTCService")
            #else
            print("⚠️ WebRTCService: Running on simulator, video capturer skipped")
            FileLogger.shared.log("⚠️ Running on simulator, video capturer skipped", category: "WebRTCService")
            #endif

            localVideoTrack = peerConnectionFactory?.videoTrack(with: localVideoSource!, trackId: "video0")
            localVideoTrack?.isEnabled = isVideoEnabled

            if let videoTrack = localVideoTrack {
                peerConnection?.add(videoTrack, streamIds: ["stream0"])
                print("✅ WebRTCService: Video track added to peer connection")
                print("   Video track ID: \(videoTrack.trackId)")
                print("   Video track kind: \(videoTrack.kind)")
                print("   Video track isEnabled: \(videoTrack.isEnabled)")
                print("   Video track readyState: \(videoTrack.readyState)")
                FileLogger.shared.log("✅ Video track added - ID:\(videoTrack.trackId) kind:\(videoTrack.kind) enabled:\(videoTrack.isEnabled) state:\(videoTrack.readyState.rawValue)", category: "WebRTCService")
            } else {
                print("❌ WebRTCService: Failed to create video track")
                FileLogger.shared.log("❌ Failed to create video track", category: "WebRTCService")
            }

            // Check if CallKit audio session is already activated
            if callKitAudioSessionActivated {
                // CallKit audio session was activated before PeerConnection setup
                print("▶️ WebRTCService: CallKit audio already active, starting camera immediately")
                FileLogger.shared.log("▶️ CallKit audio already active, starting camera immediately", category: "WebRTCService")
                cameraStartPending = false  // Clear any pending flag
                startCaptureLocalVideo()
            } else {
                // Wait for CallKit audio session activation
                cameraStartPending = true
                print("⏸️ WebRTCService: Camera start pending until CallKit audio session activation")
                FileLogger.shared.log("⏸️ Camera start pending until CallKit audio session activation", category: "WebRTCService")
            }
        } else {
            print("ℹ️ WebRTCService: Audio-only call, no video track added")
            FileLogger.shared.log("ℹ️ Audio-only call", category: "WebRTCService")
        }
    }

    /// Pre-warm the camera hardware before PeerConnection setup (for VoIP Push cold start)
    func prewarmCamera() async {
        #if !targetEnvironment(simulator)
        print("🔥 WebRTCService: Pre-warming camera hardware for VoIP Push...")
        FileLogger.shared.log("🔥 Pre-warming camera hardware", category: "WebRTCService")

        // Create a temporary capturer to warm up the camera
        let tempSource = peerConnectionFactory?.videoSource()
        let tempCapturer = RTCCameraVideoCapturer(delegate: tempSource!)

        let devices = RTCCameraVideoCapturer.captureDevices()
        guard let frontCamera = devices.first(where: { $0.position == .front }) else {
            print("❌ WebRTCService: No front camera for pre-warming")
            FileLogger.shared.log("❌ No front camera for pre-warming", category: "WebRTCService")
            return
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
        guard let format = selectBestFormat(formats) else {
            print("❌ WebRTCService: No format for pre-warming")
            return
        }

        let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
        print("🔥 WebRTCService: Starting camera pre-warm...")
        FileLogger.shared.log("🔥 Starting camera pre-warm", category: "WebRTCService")

        // Start capture to initialize hardware (async operation)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            tempCapturer.startCapture(with: frontCamera, format: format, fps: Int(fps))
            continuation.resume()
        }

        // Wait 1 second for hardware to initialize
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Stop pre-warm capture (actual capture will start in setupLocalTracks)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            tempCapturer.stopCapture()
            continuation.resume()
        }

        print("✅ WebRTCService: Camera pre-warm complete, hardware ready")
        FileLogger.shared.log("✅ Camera pre-warm complete", category: "WebRTCService")
        #endif
    }

    func startCaptureLocalVideo() {
        #if !targetEnvironment(simulator)
        print("📹 WebRTCService: Starting camera capture...")
        FileLogger.shared.log("📹 Starting camera capture", category: "WebRTCService")

        // CRITICAL: Check camera authorization status first
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("📹 WebRTCService: Camera authorization status: \(authStatus.rawValue)")
        FileLogger.shared.log("📹 Camera authorization status: \(authStatus.rawValue) (0=not determined, 1=restricted, 2=denied, 3=authorized)", category: "WebRTCService")

        if authStatus != .authorized {
            print("⚠️ WebRTCService: Camera not authorized! Status: \(authStatus.rawValue)")
            FileLogger.shared.log("⚠️ Camera not authorized! Status: \(authStatus.rawValue)", category: "WebRTCService")
        }

        guard let capturer = videoCapturer else {
            print("❌ WebRTCService: Video capturer is nil")
            FileLogger.shared.log("❌ Video capturer is nil", category: "WebRTCService")
            return
        }

        let devices = RTCCameraVideoCapturer.captureDevices()
        print("📹 WebRTCService: Found \(devices.count) camera devices")
        FileLogger.shared.log("📹 Found \(devices.count) camera devices", category: "WebRTCService")

        for (index, device) in devices.enumerated() {
            print("   Device[\(index)]: \(device.localizedName), position: \(device.position.rawValue)")
            FileLogger.shared.log("   Device[\(index)]: \(device.localizedName), position: \(device.position.rawValue)", category: "WebRTCService")
        }

        guard let frontCamera = devices.first(where: { $0.position == .front }) else {
            print("❌ WebRTCService: No front camera found")
            FileLogger.shared.log("❌ No front camera found", category: "WebRTCService")
            return
        }

        // Check if camera is locked by another app
        do {
            try frontCamera.lockForConfiguration()
            print("✅ WebRTCService: Successfully locked camera for configuration")
            FileLogger.shared.log("✅ Successfully locked camera for configuration", category: "WebRTCService")
            frontCamera.unlockForConfiguration()
        } catch {
            print("❌ WebRTCService: Failed to lock camera - it may be in use: \(error.localizedDescription)")
            FileLogger.shared.log("❌ Failed to lock camera: \(error.localizedDescription)", category: "WebRTCService")
        }

        // Select best quality format (prefer higher resolution)
        let formats = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
        print("📹 WebRTCService: Found \(formats.count) supported formats")
        FileLogger.shared.log("📹 Found \(formats.count) supported formats", category: "WebRTCService")

        guard let format = selectBestFormat(formats) else {
            print("❌ WebRTCService: No supported format for front camera")
            FileLogger.shared.log("❌ No supported format for front camera", category: "WebRTCService")
            return
        }

        // Get format dimensions for logging
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let width = dimensions.width
        let height = dimensions.height

        let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
        print("📹 WebRTCService: Starting capture at \(width)x\(height) @ \(Int(fps)) fps")
        FileLogger.shared.log("📹 Starting capture at \(width)x\(height) @ \(Int(fps)) fps", category: "WebRTCService")

        // Use completion handler to detect errors
        // CRITICAL: No completion handler available for startCapture in WebRTC
        // It starts capture asynchronously without callback
        capturer.startCapture(with: frontCamera, format: format, fps: Int(fps))

        print("✅ WebRTCService: Camera capture started (asynchronous - frames will arrive soon)")
        FileLogger.shared.log("✅ Camera capture started (asynchronous)", category: "WebRTCService")

        // DO NOT use Thread.sleep here - it blocks the main thread and prevents camera callbacks!
        // Instead, we'll wait for readyState to become 1 in the caller (CallManager)
        #else
        print("⚠️ WebRTCService: Running on simulator, camera capture skipped")
        #endif
    }

    /// Select best quality format (prefer 720p or higher, 30fps)
    private func selectBestFormat(_ formats: [AVCaptureDevice.Format]) -> AVCaptureDevice.Format? {
        // Prefer formats with:
        // 1. Resolution around 720p (1280x720) or 1080p (1920x1080)
        // 2. 30 FPS capable
        // 3. H.264 codec for compatibility

        let sortedFormats = formats.sorted { format1, format2 in
            let dims1 = CMVideoFormatDescriptionGetDimensions(format1.formatDescription)
            let dims2 = CMVideoFormatDescriptionGetDimensions(format2.formatDescription)

            let pixels1 = Int(dims1.width) * Int(dims1.height)
            let pixels2 = Int(dims2.width) * Int(dims2.height)

            // Prefer 720p (921,600 pixels) or 1080p (2,073,600 pixels)
            let target720p = 1280 * 720
            let target1080p = 1920 * 1080

            let diff1_720p = abs(pixels1 - target720p)
            let diff1_1080p = abs(pixels1 - target1080p)
            let diff2_720p = abs(pixels2 - target720p)
            let diff2_1080p = abs(pixels2 - target1080p)

            let minDiff1 = min(diff1_720p, diff1_1080p)
            let minDiff2 = min(diff2_720p, diff2_1080p)

            return minDiff1 < minDiff2
        }

        // Select first format that supports 30 FPS
        for format in sortedFormats {
            if let fpsRange = format.videoSupportedFrameRateRanges.first, fpsRange.maxFrameRate >= 30 {
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                print("📹 WebRTCService: Selected format: \(dims.width)x\(dims.height)")
                return format
            }
        }

        // Fallback to first available format
        return sortedFormats.first
    }


    func switchCamera() {
        #if !targetEnvironment(simulator)
        guard let capturer = videoCapturer else { return }

        let devices = RTCCameraVideoCapturer.captureDevices()
        let currentPosition: AVCaptureDevice.Position = devices.first?.position == .front ? .back : .front

        guard let targetCamera = devices.first(where: { $0.position == currentPosition }) else { return }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: targetCamera)
        guard let format = selectBestFormat(formats) else { return }

        let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30

        capturer.startCapture(with: targetCamera, format: format, fps: Int(fps))
        #endif
    }

    func toggleMute() {
        isAudioEnabled.toggle()
        localAudioTrack?.isEnabled = isAudioEnabled
    }

    func toggleVideo() {
        isVideoEnabled.toggle()
        localVideoTrack?.isEnabled = isVideoEnabled
    }

    func disconnect() {
        close()
    }

    // MARK: - Signaling

    // Async/await versions for modern Swift
    func setupPeerConnection(iceServers: [RTCIceServer], isVideo: Bool = true) async throws {
        setupPeerConnection(with: iceServers, isVideo: isVideo)
    }

    func createOffer(isVideo: Bool) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            createOffer(isVideo: isVideo) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create offer"]))
                }
            }
        }
    }

    func createAnswer(isVideo: Bool) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            createAnswer(isVideo: isVideo) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create answer"]))
                }
            }
        }
    }

    func setRemoteDescription(sdp: String, type: RTCSdpType) async throws {
        print("🔧 WebRTCService: Setting remote description - type: \(type)")
        print("🔍 WebRTCService: Remote SDP length: \(sdp.count)")
        print("🔍 WebRTCService: Remote SDP contains video: \(sdp.contains("m=video"))")

        // Check video line status in offer
        if let videoLineRange = sdp.range(of: "m=video [^\r\n]+", options: .regularExpression) {
            let videoLine = String(sdp[videoLineRange])
            print("🔍 WebRTCService: Remote video line: \(videoLine)")
            FileLogger.shared.log("🔧 Remote (offer) - video line: \(videoLine)", category: "WebRTCService")
        } else {
            FileLogger.shared.log("🔧 Setting remote description - type: \(type.rawValue), has video: \(sdp.contains("m=video")), length: \(sdp.count)", category: "WebRTCService")
        }

        let sessionDescription = RTCSessionDescription(type: type, sdp: sdp)
        return try await withCheckedThrowingContinuation { continuation in
            setRemoteDescription(sessionDescription) { error in
                if let error = error {
                    print("❌ WebRTCService: Failed to set remote description - \(error.localizedDescription)")
                    FileLogger.shared.log("❌ Failed to set remote description - \(error.localizedDescription)", category: "WebRTCService")
                    continuation.resume(throwing: error)
                } else {
                    print("✅ WebRTCService: Remote description set successfully")
                    FileLogger.shared.log("✅ Remote description set", category: "WebRTCService")
                    continuation.resume()
                }
            }
        }
    }

    func createOffer(isVideo: Bool, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        print("🎥 WebRTCService: Creating offer - isVideo: \(isVideo)")
        FileLogger.shared.log("🎥 Creating offer - isVideo: \(isVideo), PC exists: \(peerConnection != nil)", category: "WebRTCService")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": isVideo ? "true" : "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else {
                FileLogger.shared.log("❌ Failed to create offer - \(error?.localizedDescription ?? "unknown")", category: "WebRTCService")
                completion(nil, error)
                return
            }

            print("✅ WebRTCService: Offer SDP created, length: \(sdp.sdp.count)")
            FileLogger.shared.log("✅ Offer SDP created, length: \(sdp.sdp.count), contains video: \(sdp.sdp.contains("m=video"))", category: "WebRTCService")

            self?.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    FileLogger.shared.log("❌ Failed to set local description: \(error.localizedDescription)", category: "WebRTCService")
                } else {
                    FileLogger.shared.log("✅ Local description (offer) set successfully", category: "WebRTCService")
                }
                completion(sdp, error)
            }
        }
    }

    func createAnswer(isVideo: Bool, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        print("🎥 WebRTCService: Creating answer - isVideo: \(isVideo)")
        FileLogger.shared.log("🎥 Creating answer - isVideo: \(isVideo)", category: "WebRTCService")

        // Log detailed video track state before creating answer
        if let videoTrack = localVideoTrack {
            print("🔍 WebRTCService: Video track state before answer:")
            print("   - trackId: \(videoTrack.trackId)")
            print("   - kind: \(videoTrack.kind)")
            print("   - isEnabled: \(videoTrack.isEnabled)")
            print("   - readyState: \(videoTrack.readyState.rawValue)")
            FileLogger.shared.log("🔍 Video track before answer - id:\(videoTrack.trackId) kind:\(videoTrack.kind) enabled:\(videoTrack.isEnabled) state:\(videoTrack.readyState.rawValue)", category: "WebRTCService")
        } else {
            print("⚠️ WebRTCService: No local video track found before creating answer!")
            FileLogger.shared.log("⚠️ No local video track before creating answer", category: "WebRTCService")
        }

        // Check transceivers
        if let transceivers = peerConnection?.transceivers {
            print("🔍 WebRTCService: Found \(transceivers.count) transceivers:")
            FileLogger.shared.log("🔍 Found \(transceivers.count) transceivers", category: "WebRTCService")
            for (index, transceiver) in transceivers.enumerated() {
                let mediaType = transceiver.mediaType == .audio ? "audio" : "video"
                let direction = transceiver.direction.rawValue
                print("   Transceiver[\(index)]: \(mediaType), direction: \(direction)")
                FileLogger.shared.log("  Transceiver[\(index)]: \(mediaType), direction: \(direction)", category: "WebRTCService")
            }
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": isVideo ? "true" : "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else {
                print("❌ WebRTCService: Failed to create answer - \(error?.localizedDescription ?? "unknown error")")
                FileLogger.shared.log("❌ Failed to create answer - \(error?.localizedDescription ?? "unknown")", category: "WebRTCService")
                completion(nil, error)
                return
            }

            print("✅ WebRTCService: Answer SDP created, length: \(sdp.sdp.count)")
            print("🔍 WebRTCService: Answer SDP contains video: \(sdp.sdp.contains("m=video"))")

            // Check video line status
            if let videoLineRange = sdp.sdp.range(of: "m=video [^\r\n]+", options: .regularExpression) {
                let videoLine = String(sdp.sdp[videoLineRange])
                print("🔍 WebRTCService: Video line: \(videoLine)")
                FileLogger.shared.log("✅ Answer - video line: \(videoLine)", category: "WebRTCService")
            } else {
                FileLogger.shared.log("✅ Answer - has video: \(sdp.sdp.contains("m=video")), length: \(sdp.sdp.count)", category: "WebRTCService")
            }

            self?.peerConnection?.setLocalDescription(sdp) { error in
                if let error = error {
                    print("❌ WebRTCService: Failed to set local description - \(error.localizedDescription)")
                    FileLogger.shared.log("❌ Failed to set local description - \(error.localizedDescription)", category: "WebRTCService")
                } else {
                    print("✅ WebRTCService: Local description (answer) set successfully")
                    FileLogger.shared.log("✅ Local description set", category: "WebRTCService")
                }
                completion(sdp, error)
            }
        }
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        peerConnection?.setRemoteDescription(sdp, completionHandler: completion)
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        print("📥 WebRTCService: Adding ICE candidate - mid: \(candidate.sdpMid ?? "nil"), index: \(candidate.sdpMLineIndex)")
        FileLogger.shared.log("📥 Adding ICE candidate - mid: \(candidate.sdpMid ?? "nil"), index: \(candidate.sdpMLineIndex)", category: "WebRTCService")
        peerConnection?.add(candidate)
    }

    func close() {
        print("🔵 WebRTCService: Closing connection and cleaning up resources")
        FileLogger.shared.log("🔵 Closing connection and cleaning up resources", category: "WebRTCService")

        // Stop video capture first and wait for it to complete
        #if !targetEnvironment(simulator)
        if videoCapturer != nil {
            print("📹 WebRTCService: Stopping video capture...")
            FileLogger.shared.log("📹 Stopping video capture", category: "WebRTCService")
            videoCapturer?.stopCapture()
            // Give camera time to fully release resources
            Thread.sleep(forTimeInterval: 0.5)  // 500ms wait
            print("✅ WebRTCService: Video capture stopped")
            FileLogger.shared.log("✅ Video capture stopped", category: "WebRTCService")
        }
        #endif
        videoCapturer = nil

        peerConnection?.close()
        peerConnection = nil

        localAudioTrack = nil
        localVideoTrack = nil
        remoteVideoTrack = nil
        localVideoSource = nil

        // Reset video/audio enabled state for next call
        isVideoEnabled = true
        isAudioEnabled = true

        // Reset CallKit flags for next call
        callKitAudioSessionActivated = false
        cameraStartPending = false

        // Cancel any pending disconnect timer
        disconnectTimer?.invalidate()
        disconnectTimer = nil

        // Reset ICE state
        lastIceState = .new

        print("✅ WebRTCService: Cleanup complete")
        FileLogger.shared.log("✅ Cleanup complete - PeerConnection closed and all tracks cleared", category: "WebRTCService")
    }

    // MARK: - Helper Methods

    func getLocalVideoTrack() -> RTCVideoTrack? {
        return localVideoTrack
    }

    func getRemoteVideoTrack() -> RTCVideoTrack? {
        return remoteVideoTrack
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        let stateName: String
        switch stateChanged {
        case .stable: stateName = "stable"
        case .haveLocalOffer: stateName = "haveLocalOffer"
        case .haveLocalPrAnswer: stateName = "haveLocalPrAnswer"
        case .haveRemoteOffer: stateName = "haveRemoteOffer"
        case .haveRemotePrAnswer: stateName = "haveRemotePrAnswer"
        case .closed: stateName = "closed"
        @unknown default: stateName = "unknown(\(stateChanged.rawValue))"
        }
        print("📡 WebRTCService: Signaling state changed: \(stateName)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📺 WebRTCService: Remote stream added")
        print("   Audio tracks: \(stream.audioTracks.count)")
        print("   Video tracks: \(stream.videoTracks.count)")

        if let videoTrack = stream.videoTracks.first {
            remoteVideoTrack = videoTrack
            print("✅ WebRTCService: Remote video track assigned")
            onRemoteStreamAdded?()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📺 WebRTCService: Remote stream removed")
        remoteVideoTrack = nil
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("Peer connection should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateName: String
        switch newState {
        case .new: stateName = "new"
        case .checking: stateName = "checking"
        case .connected: stateName = "connected"
        case .completed: stateName = "completed"
        case .failed: stateName = "failed"
        case .disconnected: stateName = "disconnected"
        case .closed: stateName = "closed"
        case .count: stateName = "count"
        @unknown default: stateName = "unknown(\(newState.rawValue))"
        }
        print("🔌 WebRTCService: ICE connection state changed: \(lastIceState.rawValue) -> \(stateName)")
        FileLogger.shared.log("🔌 ICE connection state: \(stateName)", category: "WebRTCService")

        // Cancel any pending disconnect timer when state changes
        disconnectTimer?.invalidate()
        disconnectTimer = nil

        switch newState {
        case .connected, .completed:
            print("✅ WebRTCService: ICE connection established")
            FileLogger.shared.log("✅ ICE connection established", category: "WebRTCService")
            print("🔔 WebRTCService: Calling onConnected callback...")
            print("🔔 WebRTCService: onConnected is nil? \(onConnected == nil)")
            onConnected?()
            print("🔔 WebRTCService: onConnected callback invoked")

        case .disconnected:
            // Disconnected is often temporary - wait 10 seconds before ending call
            print("⚠️ WebRTCService: ICE connection disconnected - waiting 10s for reconnection")
            FileLogger.shared.log("⚠️ ICE connection disconnected - waiting 10s for reconnection", category: "WebRTCService")

            disconnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("❌ WebRTCService: ICE still disconnected after 10s - ending call")
                FileLogger.shared.log("❌ ICE still disconnected after 10s - ending call", category: "WebRTCService")
                self.onDisconnected?()
            }

        case .failed:
            // Failed might recover - longer timeout for initial connection
            // Check if we're coming from 'checking' (initial connection) vs 'connected' (reconnection)
            let isInitialConnection = (lastIceState == .new || lastIceState == .checking)
            let timeout: TimeInterval = isInitialConnection ? 20.0 : 5.0

            print("❌ WebRTCService: ICE connection failed - waiting \(Int(timeout))s for recovery (initial: \(isInitialConnection))")
            FileLogger.shared.log("❌ ICE connection failed - waiting \(Int(timeout))s for recovery (initial: \(isInitialConnection))", category: "WebRTCService")

            disconnectTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                print("❌ WebRTCService: ICE still failed after \(Int(timeout))s - ending call")
                FileLogger.shared.log("❌ ICE still failed after \(Int(timeout))s - ending call", category: "WebRTCService")
                self.onDisconnected?()
            }

        case .closed:
            // Closed is intentional - end call immediately
            print("🔌 WebRTCService: ICE connection closed")
            FileLogger.shared.log("🔌 ICE connection closed", category: "WebRTCService")
            onDisconnected?()

        case .checking:
            print("🔍 WebRTCService: ICE checking connectivity...")
            FileLogger.shared.log("🔍 ICE checking connectivity", category: "WebRTCService")

        default:
            break
        }

        lastIceState = newState
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        let stateName: String
        switch newState {
        case .new: stateName = "new"
        case .gathering: stateName = "gathering"
        case .complete: stateName = "complete"
        @unknown default: stateName = "unknown(\(newState.rawValue))"
        }
        print("🔍 WebRTCService: ICE gathering state changed: \(stateName)")
        FileLogger.shared.log("🔍 ICE gathering state: \(stateName)", category: "WebRTCService")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // ICE候補の種類を判別（host, srflx, relay）
        let candidateType: String
        if candidate.sdp.contains("typ relay") {
            candidateType = "RELAY (TURN)"
        } else if candidate.sdp.contains("typ srflx") {
            candidateType = "SERVER-REFLEXIVE (STUN)"
        } else if candidate.sdp.contains("typ host") {
            candidateType = "HOST (local)"
        } else {
            candidateType = "UNKNOWN"
        }

        // mid を解析して音声/ビデオを判別
        let mediaType: String
        if let mid = candidate.sdpMid {
            if mid == "0" {
                mediaType = "AUDIO"
            } else if mid == "1" {
                mediaType = "VIDEO"
            } else {
                mediaType = "mid:\(mid)"
            }
        } else {
            mediaType = "UNKNOWN"
        }

        print("🧊 WebRTCService: Generated ICE candidate - Type: \(candidateType), Media: \(mediaType)")
        print("   Full SDP: \(candidate.sdp)")
        FileLogger.shared.log("🧊 Generated ICE candidate - Type: \(candidateType), Media: \(mediaType), mid: \(candidate.sdpMid ?? "nil"), index: \(candidate.sdpMLineIndex)", category: "WebRTCService")
        onIceCandidate?(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Removed ICE candidates")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }
}

