//
//  WebRTCService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import Combine
import WebRTC

class WebRTCService: NSObject, ObservableObject {
    static let shared = WebRTCService()

    private var peerConnection: RTCPeerConnection?
    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var localVideoTrack: RTCVideoTrack?
    private var localAudioTrack: RTCAudioTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var videoCapturer: RTCCameraVideoCapturer?
    private var localVideoSource: RTCVideoSource?

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
            return
        }

        print("✅ WebRTCService: Peer connection created")
        setupLocalTracks(isVideo: isVideo)
    }

    private func setupLocalTracks(isVideo: Bool) {
        print("🎥 WebRTCService: Setting up local tracks - isVideo: \(isVideo)")

        // Audio track (always needed)
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = peerConnectionFactory?.audioSource(with: audioConstraints)
        localAudioTrack = peerConnectionFactory?.audioTrack(with: audioSource!, trackId: "audio0")
        localAudioTrack?.isEnabled = isAudioEnabled

        // Add audio track
        if let audioTrack = localAudioTrack {
            peerConnection?.add(audioTrack, streamIds: ["stream0"])
            print("✅ WebRTCService: Audio track added")
        }

        // Video track (only for video calls)
        if isVideo {
            localVideoSource = peerConnectionFactory?.videoSource()

            #if !targetEnvironment(simulator)
            videoCapturer = RTCCameraVideoCapturer(delegate: localVideoSource!)
            #endif

            localVideoTrack = peerConnectionFactory?.videoTrack(with: localVideoSource!, trackId: "video0")
            localVideoTrack?.isEnabled = isVideoEnabled

            if let videoTrack = localVideoTrack {
                peerConnection?.add(videoTrack, streamIds: ["stream0"])
                print("✅ WebRTCService: Video track added")
            }

            startCaptureLocalVideo()
        } else {
            print("ℹ️ WebRTCService: Audio-only call, no video track added")
        }
    }

    func startCaptureLocalVideo() {
        #if !targetEnvironment(simulator)
        print("📹 WebRTCService: Starting camera capture...")

        guard let capturer = videoCapturer else {
            print("❌ WebRTCService: Video capturer is nil")
            return
        }

        let devices = RTCCameraVideoCapturer.captureDevices()
        print("📹 WebRTCService: Found \(devices.count) camera devices")

        guard let frontCamera = devices.first(where: { $0.position == .front }) else {
            print("❌ WebRTCService: No front camera found")
            return
        }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: frontCamera)
        guard let format = formats.first else {
            print("❌ WebRTCService: No supported format for front camera")
            return
        }

        let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
        print("📹 WebRTCService: Starting capture at \(Int(fps)) fps")

        capturer.startCapture(with: frontCamera, format: format, fps: Int(fps))
        print("✅ WebRTCService: Camera capture started")
        #else
        print("⚠️ WebRTCService: Running on simulator, camera capture skipped")
        #endif
    }

    func switchCamera() {
        #if !targetEnvironment(simulator)
        guard let capturer = videoCapturer else { return }

        let devices = RTCCameraVideoCapturer.captureDevices()
        let currentPosition: AVCaptureDevice.Position = devices.first?.position == .front ? .back : .front

        guard let targetCamera = devices.first(where: { $0.position == currentPosition }) else { return }

        let formats = RTCCameraVideoCapturer.supportedFormats(for: targetCamera)
        guard let format = formats.first else { return }

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
        let sessionDescription = RTCSessionDescription(type: type, sdp: sdp)
        return try await withCheckedThrowingContinuation { continuation in
            setRemoteDescription(sessionDescription) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func createOffer(isVideo: Bool, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        print("🎥 WebRTCService: Creating offer - isVideo: \(isVideo)")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": isVideo ? "true" : "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.offer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else {
                completion(nil, error)
                return
            }

            self?.peerConnection?.setLocalDescription(sdp) { error in
                completion(sdp, error)
            }
        }
    }

    func createAnswer(isVideo: Bool, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        print("🎥 WebRTCService: Creating answer - isVideo: \(isVideo)")

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": isVideo ? "true" : "false"
            ],
            optionalConstraints: nil
        )

        peerConnection?.answer(for: constraints) { [weak self] sdp, error in
            guard let sdp = sdp else {
                completion(nil, error)
                return
            }

            self?.peerConnection?.setLocalDescription(sdp) { error in
                completion(sdp, error)
            }
        }
    }

    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        peerConnection?.setRemoteDescription(sdp, completionHandler: completion)
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        peerConnection?.add(candidate)
    }

    func close() {
        print("🔵 WebRTCService: Closing connection and cleaning up resources")

        videoCapturer?.stopCapture()
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

        print("✅ WebRTCService: Cleanup complete")
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
        print("🔌 WebRTCService: ICE connection state changed: \(stateName)")

        switch newState {
        case .connected, .completed:
            print("✅ WebRTCService: ICE connection established")
            print("🔔 WebRTCService: Calling onConnected callback...")
            print("🔔 WebRTCService: onConnected is nil? \(onConnected == nil)")
            onConnected?()
            print("🔔 WebRTCService: onConnected callback invoked")
        case .disconnected:
            print("⚠️ WebRTCService: ICE connection disconnected")
            onDisconnected?()
        case .failed:
            print("❌ WebRTCService: ICE connection failed")
            onDisconnected?()
        case .closed:
            print("🔌 WebRTCService: ICE connection closed")
            onDisconnected?()
        case .checking:
            print("🔍 WebRTCService: ICE checking connectivity...")
        default:
            break
        }
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

        print("🧊 WebRTCService: Generated ICE candidate - Type: \(candidateType)")
        print("   SDP: \(candidate.sdp)")
        onIceCandidate?(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("Removed ICE candidates")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("Data channel opened")
    }
}
