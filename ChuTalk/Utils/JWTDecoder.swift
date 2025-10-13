//
//  JWTDecoder.swift
//  ChuTalk
//
//  Created by Claude Code
//

import Foundation

class JWTDecoder {
    static func decode(token: String) -> JWTPayload? {
        let segments = token.components(separatedBy: ".")
        guard segments.count == 3 else {
            print("❌ Invalid JWT token format")
            return nil
        }

        // Decode the payload (second segment)
        let payloadSegment = segments[1]

        // Add padding if needed
        var base64 = payloadSegment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let paddingLength = 4 - base64.count % 4
        if paddingLength < 4 {
            base64.append(contentsOf: repeatElement("=", count: paddingLength))
        }

        guard let data = Data(base64Encoded: base64) else {
            print("❌ Failed to decode base64")
            return nil
        }

        do {
            let payload = try JSONDecoder().decode(JWTPayload.self, from: data)
            print("✅ JWT decoded: uid=\(payload.uid), username=\(payload.u)")
            return payload
        } catch {
            print("❌ Failed to decode JWT payload: \(error)")
            return nil
        }
    }
}
