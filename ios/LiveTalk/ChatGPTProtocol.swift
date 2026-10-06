import Foundation

enum ChatGPTError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct OAuthCallback {
    let code: String
    let clientID: String
    static func parse(_ target: String, state: String, originalClient: String?) throws -> OAuthCallback {
        guard target.utf8.count <= 16384, target.hasPrefix("/auth/callback?"),
              let url = URLComponents(string: "http://127.0.0.1" + target), url.path == "/auth/callback" else {
            throw ChatGPTError.message("ログインの戻り先を確認できませんでした。")
        }
        var fields = [String: String]()
        for item in url.queryItems ?? [] {
            guard fields[item.name] == nil, let value = item.value else { throw ChatGPTError.message("ログインの確認情報が正しくありません。") }
            fields[item.name] = value
        }
        guard constantEqual(fields["state"] ?? "", state) else { throw ChatGPTError.message("ログインの確認情報が一致しません。もう一度ログインしてください。") }
        if fields["error"] != nil { throw ChatGPTError.message("ChatGPTでの許可が完了しませんでした。利用枠の使用を許可して、もう一度お試しください。") }
        guard let code = fields["code"], !code.isEmpty, code.count <= 4096,
              let client = fields["client_id"] ?? originalClient, client != "dynamic_agent_client",
              client.range(of: "^[A-Za-z0-9_-]{8,256}$", options: .regularExpression) != nil,
              originalClient == nil || originalClient == client else { throw ChatGPTError.message("ChatGPTの登録を確認できませんでした。") }
        return OAuthCallback(code: code, clientID: client)
    }
    private static func constantEqual(_ a: String, _ b: String) -> Bool {
        let aa = Array(a.utf8), bb = Array(b.utf8); guard aa.count == bb.count else { return false }
        var diff: UInt8 = 0; for i in aa.indices { diff |= aa[i] ^ bb[i] }; return diff == 0
    }
}

struct SSEDecoder {
    private var dataLines = [String]()
    private var size = 0
    private var lineBytes = [UInt8]()
    private var afterCR = false
    mutating func byte(_ value: UInt8) throws -> String? {
        if value == 10 && afterCR { afterCR = false; return nil }
        afterCR = value == 13
        if value == 10 || value == 13 {
            guard let text = String(bytes: lineBytes, encoding: .utf8) else { throw ChatGPTError.message("返答の文字を確認できませんでした。") }
            lineBytes.removeAll(keepingCapacity: true)
            return try line(text)
        }
        guard lineBytes.count < 262150 else { throw ChatGPTError.message("返答のデータが大きすぎます。会話を再開してください。") }
        lineBytes.append(value)
        return nil
    }
    mutating func line(_ line: String) throws -> String? {
        if line.isEmpty { let result = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n"); dataLines = []; size = 0; return result }
        if line.hasPrefix("data:") {
            let value = String(line.dropFirst(5)).replacingOccurrences(of: "^ ", with: "", options: .regularExpression)
            size += value.utf8.count
            guard size <= 262144 else { throw ChatGPTError.message("返答のデータが大きすぎます。会話を再開してください。") }
            dataLines.append(value)
        }
        return nil
    }
}

enum PlanUsageError {
    static func text(code: String?, status: Int? = nil) -> String {
        if code == "subscription_sharing_usage_limit_exceeded" || status == 429 { return "ChatGPTの利用上限に達しました。「利用枠を確認」から確認してください。" }
        if code == "subscription_sharing_usage_unavailable" { return "このアカウントではChatGPTの利用枠を使えません。ChatGPTの設定でアプリへの許可を確認してください。" }
        if status == 401 || status == 403 { return "ChatGPTの接続許可を確認できません。もう一度ログインしてください。" }
        return "ChatGPTの返答を完了できませんでした。接続を確認して会話を再開してください。"
    }
}
