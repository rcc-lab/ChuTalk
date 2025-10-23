//
//  APIService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation
import UIKit
import AVFoundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized access"
        case .serverError(let message):
            return message
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

class APIService {
    static let shared = APIService()
    private var isAutoReloginInProgress = false  // 同時実行防止

    private init() {}

    private func request<T: Decodable>(
        url: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        requiresAuth: Bool = false,
        isRetry: Bool = false  // 再試行フラグ
    ) async throws -> T {
        let urlString = url  // 元のURL文字列を保存（再試行用）
        guard let urlObject = URL(string: url) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: urlObject)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            guard let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            print("📡 Response status: \(httpResponse.statusCode)")
            if let dataString = String(data: data, encoding: .utf8) {
                // Truncate very long responses
                let maxLength = 500
                if dataString.count > maxLength {
                    print("📡 Response data (truncated): \(dataString.prefix(maxLength))...")
                } else {
                    print("📡 Response data: \(dataString)")
                }
            }

            if httpResponse.statusCode == 401 {
                // 401エラー: トークン期限切れ
                if !isRetry && requiresAuth {
                    // 初回の401エラー → 自動再ログインを試行
                    print("⚠️ APIService: 401 Unauthorized - attempting auto re-login...")

                    if try await attemptAutoRelogin() {
                        // 再ログイン成功 → 元のリクエストを再試行
                        print("✅ APIService: Auto re-login successful, retrying request...")
                        return try await self.request(
                            url: urlString,  // 元のURL文字列を使用
                            method: method,
                            body: body,
                            requiresAuth: requiresAuth,
                            isRetry: true  // 再試行フラグをON
                        )
                    }
                }
                // 再ログイン失敗 or 2回目の401エラー
                print("❌ APIService: Unauthorized - auto re-login failed or not attempted")
                throw APIError.unauthorized
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = errorDict["message"] as? String {
                    throw APIError.serverError(message)
                }
                throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let result = try decoder.decode(T.self, from: data)
                print("✅ Successfully decoded response")
                return result
            } catch {
                print("❌ Decoding error: \(error)")
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Authentication

    func register(username: String, password: String, displayName: String) async throws -> RegisterResponse {
        print("🔵 Registering user: \(username)")
        print("🔵 Display name: \(displayName)")
        print("🔵 Password length: \(password.count)")
        print("🔵 Password (DEBUG): \(password)")
        FileLogger.shared.log("Registration - username: \(username), displayName: \(displayName), password: \(password)", category: "APIService")

        do {
            let response: RegisterResponse = try await request(
                url: Constants.API.register,
                method: "POST",
                body: [
                    "username": username,
                    "password": password,
                    "display_name": displayName  // サーバーはスネークケースを期待
                ]
            )
            print("✅ Registration response: ok=\(response.ok), message=\(response.message ?? "nil")")
            FileLogger.shared.log("✅ Registration successful for user: \(username)", category: "APIService")
            return response
        } catch {
            print("❌ Registration error: \(error)")
            FileLogger.shared.log("❌ Registration failed for user: \(username) - Error: \(error)", category: "APIService")
            throw error
        }
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        print("🔵 APIService: Logging in user: \(username)")
        print("🔵 APIService: Password length: \(password.count)")
        print("🔵 APIService: Password (DEBUG): \(password)")
        FileLogger.shared.log("Login attempt - username: \(username), password length: \(password.count), password: \(password)", category: "APIService")

        do {
            let response: AuthResponse = try await request(
                url: Constants.API.login,
                method: "POST",
                body: [
                    "username": username,
                    "password": password
                ]
            )
            print("✅ APIService: Login successful, token received")
            FileLogger.shared.log("✅ Login successful for user: \(username)", category: "APIService")
            return response
        } catch {
            print("❌ APIService: Login failed - \(error)")
            FileLogger.shared.log("❌ Login failed for user: \(username) - Error: \(error)", category: "APIService")
            throw error
        }
    }

    // MARK: - TURN Credentials

    func getTurnCredentials() async throws -> TurnCredentials {
        return try await request(
            url: Constants.API.turnCredentials,
            requiresAuth: true
        )
    }

    // MARK: - Contacts

    func getContacts() async throws -> [Contact] {
        return try await request(
            url: Constants.API.contacts,
            requiresAuth: true
        )
    }

    func addContact(targetUsername: String) async throws -> AddContactResponse {
        return try await request(
            url: Constants.API.contacts,
            method: "POST",
            body: ["username": targetUsername],
            requiresAuth: true
        )
    }

    func deleteContact(contactId: Int) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            url: "\(Constants.API.contacts)/\(contactId)",
            method: "DELETE",
            requiresAuth: true
        )
    }

    // MARK: - Profile

    func updateProfileImage(_ imageUrl: String) async throws -> User {
        return try await request(
            url: "\(Constants.Server.baseURL)/api/users/profile",
            method: "PUT",
            body: ["profile_image_url": imageUrl],
            requiresAuth: true
        )
    }

    // MARK: - Reports

    func reportUser(reportedUserId: Int, messageId: Int?, reason: String) async throws -> ReportResponse {
        var body: [String: Any] = [
            "reported_user_id": reportedUserId,
            "reason": reason
        ]

        if let messageId = messageId {
            body["message_id"] = messageId
        }

        return try await request(
            url: "\(Constants.Server.baseURL)/api/reports",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    // MARK: - Blocking

    func blockUser(userId: Int) async throws -> ReportResponse {
        return try await request(
            url: "\(Constants.Server.baseURL)/api/blocks",
            method: "POST",
            body: ["blocked_user_id": userId],
            requiresAuth: true
        )
    }

    func unblockUser(userId: Int) async throws -> ReportResponse {
        return try await request(
            url: "\(Constants.Server.baseURL)/api/blocks/\(userId)",
            method: "DELETE",
            requiresAuth: true
        )
    }

    func getBlockedUsers() async throws -> [Contact] {
        return try await request(
            url: "\(Constants.Server.baseURL)/api/blocks",
            requiresAuth: true
        )
    }

    // MARK: - Messages

    func getMessages(userId: Int) async throws -> [Message] {
        return try await request(
            url: "\(Constants.API.messages)/\(userId)",
            requiresAuth: true
        )
    }

    func sendMessage(receiverId: Int, body: String, messageType: String = "text", imageUrl: String? = nil, videoUrl: String? = nil) async throws -> Message {
        var requestBody: [String: Any] = [
            "receiver_id": receiverId,
            "body": body,
            "message_type": messageType
        ]

        if let imageUrl = imageUrl {
            requestBody["image_url"] = imageUrl
        }

        if let videoUrl = videoUrl {
            requestBody["video_url"] = videoUrl
        }

        return try await request(
            url: Constants.API.messages,
            method: "POST",
            body: requestBody,
            requiresAuth: true
        )
    }

    func deleteMessages(userId: Int) async throws {
        struct DeleteResponse: Codable {
            let ok: Bool
        }
        print("🗑️ APIService: Deleting messages for userId: \(userId)")
        let response: DeleteResponse = try await request(
            url: "\(Constants.API.messages)/\(userId)",
            method: "DELETE",
            requiresAuth: true
        )
        print("🗑️ APIService: Delete response: ok=\(response.ok)")
    }

    func markMessagesAsRead(userId: Int) async throws {
        struct ReadResponse: Codable {
            let ok: Bool
            let count: Int?
        }
        print("👁️ APIService: Marking messages as read for userId: \(userId)")
        let response: ReadResponse = try await request(
            url: "\(Constants.API.messages)/\(userId)/read",
            method: "PUT",
            requiresAuth: true
        )
        print("👁️ APIService: Server marked \(response.count ?? 0) messages as read for user \(userId)")
    }

    // MARK: - Image Upload

    func uploadImage(_ image: UIImage) async throws -> String {
        print("📤 APIService: Starting image upload")
        FileLogger.shared.log("📤 Starting image upload", category: "APIService")

        // Resize image if too large (max 2000px on longest side)
        let maxDimension: CGFloat = 2000
        let resizedImage: UIImage

        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()

            print("📐 APIService: Resized image from \(image.size) to \(newSize)")
            FileLogger.shared.log("📐 Resized image from \(image.size) to \(newSize)", category: "APIService")
        } else {
            resizedImage = image
        }

        // Try different compression qualities until size is acceptable (max 5MB)
        let maxSize = 5 * 1024 * 1024 // 5MB
        var compressionQuality: CGFloat = 0.8
        var imageData = resizedImage.jpegData(compressionQuality: compressionQuality)

        while let data = imageData, data.count > maxSize && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            imageData = resizedImage.jpegData(compressionQuality: compressionQuality)
            print("🗜️ APIService: Trying compression quality \(compressionQuality), size: \(data.count) bytes")
        }

        guard let finalImageData = imageData else {
            print("❌ APIService: Failed to convert image to JPEG data")
            FileLogger.shared.log("❌ Failed to convert image to JPEG data", category: "APIService")
            throw APIError.invalidURL
        }

        print("✅ APIService: Image converted to JPEG (\(finalImageData.count) bytes, quality: \(compressionQuality))")
        FileLogger.shared.log("✅ Image converted to JPEG (\(finalImageData.count) bytes, quality: \(compressionQuality))", category: "APIService")

        let boundary = UUID().uuidString
        let uploadURL = "\(Constants.Server.baseURL)/api/upload"
        print("📤 APIService: Upload URL: \(uploadURL)")

        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0 // 60 seconds timeout for large uploads

        guard let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) else {
            print("❌ APIService: No auth token found")
            FileLogger.shared.log("❌ No auth token found", category: "APIService")
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        print("✅ APIService: Auth token added")

        var body = Data()

        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(finalImageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        print("✅ APIService: Request body prepared (\(body.count) bytes)")
        FileLogger.shared.log("✅ Request body prepared (\(body.count) bytes)", category: "APIService")

        print("📤 APIService: Sending upload request...")
        FileLogger.shared.log("📤 Sending upload request to \(uploadURL)", category: "APIService")

        let (data, response) = try await URLSession.shared.data(for: request)
        print("✅ APIService: Received response")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ APIService: Invalid HTTP response")
            throw APIError.invalidResponse
        }

        print("📊 APIService: HTTP Status Code: \(httpResponse.statusCode)")
        FileLogger.shared.log("📊 HTTP Status Code: \(httpResponse.statusCode)", category: "APIService")

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ APIService: Server error - Status: \(httpResponse.statusCode)")
            print("❌ APIService: Response body: \(responseString)")
            FileLogger.shared.log("❌ Server error - Status: \(httpResponse.statusCode), Body: \(responseString)", category: "APIService")

            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorDict["message"] as? String {
                throw APIError.serverError(message)
            }
            throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
        }

        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        print("📊 APIService: Response body: \(responseString)")
        FileLogger.shared.log("📊 Response body: \(responseString)", category: "APIService")

        struct UploadResponse: Codable {
            let imageUrl: String

            enum CodingKeys: String, CodingKey {
                case imageUrl = "image_url"
            }
        }

        let decoder = JSONDecoder()
        do {
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
            print("✅ APIService: Image uploaded successfully: \(uploadResponse.imageUrl)")
            FileLogger.shared.log("✅ Image uploaded successfully: \(uploadResponse.imageUrl)", category: "APIService")
            return uploadResponse.imageUrl
        } catch {
            print("❌ APIService: Failed to decode response: \(error)")
            print("❌ APIService: Response data: \(responseString)")
            FileLogger.shared.log("❌ Failed to decode response: \(error), Data: \(responseString)", category: "APIService")
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Video Upload

    private func compressVideo(url: URL) async throws -> URL {
        print("🎬 APIService: Starting video compression")
        FileLogger.shared.log("🎬 Starting video compression", category: "APIService")

        let asset = AVURLAsset(url: url)

        // Check if video needs compression
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            print("⚠️ APIService: No video track found, using original")
            return url
        }

        // Get file size
        let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        let fileSizeMB = Double(fileSize ?? 0) / (1024 * 1024)
        print("📊 APIService: Original video size: \(String(format: "%.2f", fileSizeMB)) MB")

        // If file is already small enough (< 50MB), don't compress
        if fileSizeMB < 50 {
            print("✅ APIService: Video is small enough, skipping compression")
            return url
        }

        // Create export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else {
            print("⚠️ APIService: Cannot create export session, using original")
            return url
        }

        // Create temporary output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Export video
        await exportSession.export()

        if exportSession.status == .completed {
            let compressedSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64 ?? 0
            let compressedSizeMB = Double(compressedSize ?? 0) / (1024 * 1024)
            print("✅ APIService: Video compressed: \(String(format: "%.2f", fileSizeMB)) MB → \(String(format: "%.2f", compressedSizeMB)) MB")
            FileLogger.shared.log("✅ Video compressed: \(String(format: "%.2f", fileSizeMB)) MB → \(String(format: "%.2f", compressedSizeMB)) MB", category: "APIService")
            return outputURL
        } else {
            print("⚠️ APIService: Compression failed (\(exportSession.status.rawValue)), using original")
            if let error = exportSession.error {
                print("⚠️ APIService: Compression error: \(error)")
            }
            return url
        }
    }

    func uploadVideo(url: URL) async throws -> String {
        print("📤 APIService: Starting video upload")
        FileLogger.shared.log("📤 Starting video upload", category: "APIService")

        // Compress video first
        let compressedURL = try await compressVideo(url: url)

        let videoData: Data
        do {
            videoData = try Data(contentsOf: compressedURL)
            print("✅ APIService: Video data loaded (\(videoData.count) bytes)")
            FileLogger.shared.log("✅ Video data loaded (\(videoData.count) bytes)", category: "APIService")

            // Clean up temporary compressed file if different from original
            if compressedURL != url {
                try? FileManager.default.removeItem(at: compressedURL)
            }
        } catch {
            print("❌ APIService: Failed to load video data: \(error)")
            FileLogger.shared.log("❌ Failed to load video data: \(error)", category: "APIService")
            throw error
        }

        let boundary = UUID().uuidString
        let uploadURL = "\(Constants.Server.baseURL)/api/upload"
        print("📤 APIService: Upload URL: \(uploadURL)")

        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) else {
            print("❌ APIService: No auth token found")
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        print("✅ APIService: Auth token added")

        var body = Data()

        // Add video data
        let filename = url.lastPathComponent
        let mimeType = "video/mp4"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        print("✅ APIService: Request body prepared (\(body.count) bytes)")

        print("📤 APIService: Sending upload request...")

        let (data, response) = try await URLSession.shared.data(for: request)
        print("✅ APIService: Received response")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ APIService: Invalid HTTP response")
            throw APIError.invalidResponse
        }

        print("📊 APIService: HTTP Status Code: \(httpResponse.statusCode)")
        FileLogger.shared.log("📊 HTTP Status Code: \(httpResponse.statusCode)", category: "APIService")

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("❌ APIService: Server error - Status: \(httpResponse.statusCode)")
            print("❌ APIService: Response body: \(responseString)")
            FileLogger.shared.log("❌ Server error - Status: \(httpResponse.statusCode), Body: \(responseString)", category: "APIService")

            if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorDict["message"] as? String {
                throw APIError.serverError(message)
            }
            throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
        }

        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        print("📊 APIService: Response body: \(responseString)")
        FileLogger.shared.log("📊 Response body: \(responseString)", category: "APIService")

        struct UploadResponse: Codable {
            let videoUrl: String

            enum CodingKeys: String, CodingKey {
                case videoUrl = "video_url"
            }
        }

        let decoder = JSONDecoder()
        do {
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
            print("✅ APIService: Video uploaded successfully: \(uploadResponse.videoUrl)")
            FileLogger.shared.log("✅ Video uploaded successfully: \(uploadResponse.videoUrl)", category: "APIService")
            return uploadResponse.videoUrl
        } catch {
            print("❌ APIService: Failed to decode response: \(error)")
            print("❌ APIService: Response data: \(responseString)")
            FileLogger.shared.log("❌ Failed to decode response: \(error), Data: \(responseString)", category: "APIService")
            throw APIError.decodingError(error)
        }
    }

    // MARK: - User Search

    func searchUsers(query: String) async throws -> [Contact] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        return try await request(
            url: "\(Constants.API.userSearch)?q=\(encodedQuery)",
            requiresAuth: true
        )
    }

    // MARK: - Calls

    func recordCall(calleeId: Int, callType: String) async throws -> CallHistory {
        return try await request(
            url: Constants.API.calls,
            method: "POST",
            body: [
                "callee_id": calleeId,
                "call_type": callType
            ],
            requiresAuth: true
        )
    }

    func getCallHistory() async throws -> [CallHistory] {
        print("📞 APIService: Fetching call history from \(Constants.API.calls)")
        let history: [CallHistory] = try await request(
            url: Constants.API.calls,
            method: "GET",
            requiresAuth: true
        )
        print("📞 APIService: Successfully decoded \(history.count) call history items")
        return history
    }

    // MARK: - Device Token Registration

    func registerVoIPDeviceToken(voipDeviceToken: String, bundleId: String, platform: String) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            url: "\(Constants.Server.apiURL)/me/devices",
            method: "PUT",
            body: [
                "voipDeviceToken": voipDeviceToken,
                "bundleId": bundleId,
                "platform": platform
            ],
            requiresAuth: true
        )
        print("✅ APIService: VoIP device token registered")
    }

    // MARK: - Call Signaling

    func sendSignal(callId: String, action: String, data: [String: Any]) async throws {
        struct EmptyResponse: Codable {}
        let _: EmptyResponse = try await request(
            url: Constants.API.callSignal,
            method: "POST",
            body: [
                "callId": callId,
                "action": action,
                "data": data
            ],
            requiresAuth: true
        )
    }

    func getSignals(callId: String) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return json
    }

    // offerシグナルのSDPを直接取得（両方のレスポンス形式に対応）
    func getOfferSDP(callId: String) async throws -> String? {
        guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        // 形式1: オブジェクト形式 {"offer": {"sdp": "..."}, "candidates": [...]}
        if let jsonDict = jsonObject as? [String: Any],
           let offer = jsonDict["offer"] as? [String: Any],
           let sdp = offer["sdp"] as? String,
           !sdp.isEmpty {
            print("✅ APIService: Found offer SDP (object format)")
            return sdp
        }

        // 形式2: 配列形式 [{"action": "offer", "data": {"sdp": "..."}}]
        if let jsonArray = jsonObject as? [[String: Any]] {
            for signal in jsonArray {
                if let action = signal["action"] as? String,
                   action == "offer",
                   let signalData = signal["data"] as? [String: Any],
                   let sdp = signalData["sdp"] as? String,
                   !sdp.isEmpty {
                    print("✅ APIService: Found offer SDP (array format)")
                    return sdp
                }
            }
        }

        print("⚠️ APIService: No offer SDP found in response")
        return nil
    }

    // MARK: - Answer SDP

    func saveAnswer(callId: String, sdp: String, from: Int, to: Int) async throws {
        guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "action": "answer",
            "data": [
                "sdp": sdp,
                "from": from,
                "to": to
            ]
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw APIError.serverError("Server returned status code: \(httpResponse.statusCode)")
        }

        print("✅ APIService: Answer saved to API for callId: \(callId)")
    }

    func getAnswerSDP(callId: String) async throws -> String? {
        guard let url = URL(string: "\(Constants.API.callSignal)/\(callId)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = KeychainManager.shared.get(key: Constants.Keychain.authToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            return nil
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        // 形式1: オブジェクト形式 {"offer": {...}, "answer": {"sdp": "..."}, "candidates": [...]}
        if let jsonDict = jsonObject as? [String: Any],
           let answer = jsonDict["answer"] as? [String: Any],
           let sdp = answer["sdp"] as? String,
           !sdp.isEmpty {
            print("✅ APIService: Found answer SDP (object format)")
            return sdp
        }

        // 形式2: 配列形式 [{"action": "answer", "data": {"sdp": "..."}}]
        if let jsonArray = jsonObject as? [[String: Any]] {
            for signal in jsonArray {
                if let action = signal["action"] as? String,
                   action == "answer",
                   let signalData = signal["data"] as? [String: Any],
                   let sdp = signalData["sdp"] as? String,
                   !sdp.isEmpty {
                    print("✅ APIService: Found answer SDP (array format)")
                    return sdp
                }
            }
        }

        return nil
    }

    // MARK: - Auto Re-login

    /// 自動再ログイン機能（LINEのように再ログイン不要にする）
    private func attemptAutoRelogin() async throws -> Bool {
        // 同時実行防止
        guard !isAutoReloginInProgress else {
            print("⚠️ APIService: Auto re-login already in progress, skipping...")
            return false
        }

        isAutoReloginInProgress = true
        defer { isAutoReloginInProgress = false }

        // Keychainから保存されたusername/passwordを取得
        guard let username = KeychainManager.shared.get(key: Constants.Keychain.username),
              let password = KeychainManager.shared.get(key: Constants.Keychain.password) else {
            print("❌ APIService: No saved credentials for auto re-login")
            return false
        }

        print("🔄 APIService: Attempting auto re-login for user: \(username)")

        do {
            // AuthServiceのlogin関数を呼び出して再ログイン
            try await AuthService.shared.login(username: username, password: password)
            print("✅ APIService: Auto re-login successful!")
            return true
        } catch {
            print("❌ APIService: Auto re-login failed: \(error.localizedDescription)")
            return false
        }
    }
}
