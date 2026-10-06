import Foundation
import CryptoKit
import Security

enum OpenAIIdentity {
    static func decode(_ text: String) -> Data? {
        guard text.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
        let raw = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: raw + String(repeating: "=", count: (4 - raw.count % 4) % 4))
    }
    static func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    static func random(_ count: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw ChatGPTError.message("安全なログイン情報を作れませんでした。") }
        return encode(Data(bytes))
    }
    static func verify(token: String, keys: [[String: Any]], client: String, nonce: String, now: TimeInterval = Date().timeIntervalSince1970) throws -> [String: Any] {
        func invalid() -> ChatGPTError { .message("ChatGPTの本人確認を検証できませんでした。もう一度ログインしてください。") }
        guard token.utf8.count <= 65536 else { throw invalid() }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, let headerData = decode(parts[0]), let payload = decode(parts[1]), let signature = decode(parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any], let kid = header["kid"] as? String,
              let jwk = keys.first(where: { $0["kid"] as? String == kid && ($0["use"] as? String ?? "sig") == "sig" }),
              header["alg"] as? String == "RS256", jwk["kty"] as? String == "RSA",
              (jwk["alg"] as? String ?? "RS256") == "RS256", let n = jwk["n"] as? String, let e = jwk["e"] as? String,
              let modulus = decode(n), modulus.count >= 256, modulus.count <= 1024, let exponent = decode(e), !exponent.isEmpty, exponent.count <= 8 else { throw invalid() }
        let publicData = der(0x30, integer(modulus) + integer(exponent))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(publicData as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw invalid() }
        let audience = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard claims["iss"] as? String == "https://auth.openai.com", audience.contains(client),
              audience.count == 1 || claims["azp"] as? String == client,
              claims["nonce"] as? String == nonce, let subject = claims["sub"] as? String, !subject.isEmpty,
              let expiration = claims["exp"] as? Double, expiration.isFinite, expiration > now - 5,
              let issued = claims["iat"] as? Double, issued.isFinite, issued <= now + 5 else { throw invalid() }
        if let nbf = claims["nbf"] as? Double, nbf > now + 5 { throw invalid() }
        return claims
    }
    private static func integer(_ data: Data) -> Data {
        var bytes = Array(data); while bytes.count > 1 && bytes[0] == 0 { bytes.removeFirst() }
        if (bytes.first ?? 0) >= 128 { bytes.insert(0, at: 0) }; return der(0x02, Data(bytes))
    }
    private static func der(_ tag: UInt8, _ content: Data) -> Data {
        var prefix = Data([tag]); var length = content.count
        if length < 128 { prefix.append(UInt8(length)) }
        else { var bytes = [UInt8](); while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }; prefix.append(UInt8(128 + bytes.count)); prefix.append(contentsOf: bytes) }
        return prefix + content
    }
}
