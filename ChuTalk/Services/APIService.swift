//
//  APIService.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

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

    private init() {}

    private func request<T: Decodable>(
        url: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
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
                print("📡 Response data: \(dataString)")
            }

            if httpResponse.statusCode == 401 {
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
        do {
            let response: RegisterResponse = try await request(
                url: Constants.API.register,
                method: "POST",
                body: [
                    "username": username,
                    "password": password,
                    "displayName": displayName
                ]
            )
            print("✅ Registration response: ok=\(response.ok), message=\(response.message ?? "nil")")
            return response
        } catch {
            print("❌ Registration error: \(error)")
            throw error
        }
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        print("🔵 APIService: Logging in user: \(username)")
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
            return response
        } catch {
            print("❌ APIService: Login failed - \(error)")
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

    // MARK: - Messages

    func getMessages(userId: Int) async throws -> [Message] {
        return try await request(
            url: "\(Constants.API.messages)/\(userId)",
            requiresAuth: true
        )
    }

    func sendMessage(receiverId: Int, body: String) async throws -> Message {
        return try await request(
            url: Constants.API.messages,
            method: "POST",
            body: [
                "receiver_id": receiverId,
                "body": body
            ],
            requiresAuth: true
        )
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
}
