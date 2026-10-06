import UIKit
import SafariServices
import Network
import Security
import CryptoKit

private struct ChatGPTCredential: Codable {
    var clientID: String
    var subject: String
    var label: String
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var expiresAt: Double
    var scopes: [String]
}
private struct ChatGPTVault: Codable {
    var hostID = "urn:uuid:" + UUID().uuidString.lowercased()
    var accounts = [ChatGPTCredential]()
    var selectedClient: String?
}

private enum CredentialStore {
    static let service = "jp.livetalk.mobile.chatgpt-plan"
    static func query() -> [CFString: Any] { [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "registrations"] }
    static func read() throws -> ChatGPTVault {
        var fields = query(); fields[kSecReturnData] = true; fields[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(fields as CFDictionary, &result)
        if status == errSecItemNotFound { return ChatGPTVault() }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 524288,
              let vault = try? JSONDecoder().decode(ChatGPTVault.self, from: data) else { throw ChatGPTError.message("保存したChatGPT接続を読み込めません。iPhoneのロックを解除してお試しください。") }
        return vault
    }
    static func save(_ vault: ChatGPTVault) throws {
        let data = try JSONEncoder().encode(vault)
        guard data.count <= 524288 else { throw ChatGPTError.message("保存するアカウント情報が大きすぎます。") }
        let updates: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query() as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound { var fields = query(); updates.forEach { fields[$0.key] = $0.value }; status = SecItemAdd(fields as CFDictionary, nil) }
        guard status == errSecSuccess else { throw ChatGPTError.message("ChatGPTの接続を安全に保存できませんでした。iPhoneのロックを解除してお試しください。") }
    }
}

private final class NoRedirectSession: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class ChatGPTConnection: NSObject, SFSafariViewControllerDelegate {
    private var vault = ChatGPTVault()
    private var storageError: Error?
    private let session: URLSession
    private let emit: ([String: Any]) -> Void
    private var modelChoices = [[String: String]]()
    private var model = ""
    private var history = ConversationMemory()
    private var responseTask: Task<Void, Never>?
    private var responseWatchdog: Task<Void, Never>?
    private var refreshTask: Task<ChatGPTCredential, Error>?
    private var epoch = 0
    private var listener: OAuthLoopback?
    private var safari: SFSafariViewController?
    private var loginContinuation: CheckedContinuation<[String: Any], Error>?
    private var loginTimer: Task<Void, Never>?
    private var pendingState = ""
    private var pendingClient: String?
    private var pendingNonce = ""
    private var pendingVerifier = ""
    private var pendingRedirect = ""
    private var loginConsuming = false
    private var loginEpoch = 0

    init(emit: @escaping ([String: Any]) -> Void) {
        self.emit = emit
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
        config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 180
        session = URLSession(configuration: config, delegate: NoRedirectSession(), delegateQueue: nil)
        super.init()
        do { vault = try CredentialStore.read() } catch { storageError = error }
    }
    private var selected: ChatGPTCredential? { vault.accounts.first { $0.clientID == vault.selectedClient } }
    private func event(_ value: [String: Any]) { var e = value; e["provider"] = "official"; emit(e) }
    private func save(_ next: ChatGPTVault) throws { try CredentialStore.save(next); vault = next }
    private func form(_ values: [String: String]) -> Data {
        var components = URLComponents(); components.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    private func request(_ url: String, form values: [String: String]? = nil, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let values { request.httpMethod = "POST"; request.httpBody = form(values); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }; return request
    }
    private func object(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard data.count <= 524288, let http = response as? HTTPURLResponse else { throw ChatGPTError.message("ChatGPTからの接続情報を確認できませんでした。") }
        let value = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let code = ((value["error"] as? [String: Any])?["code"] as? String) ?? value["error"] as? String
            throw ChatGPTError.message(PlanUsageError.text(code: code, status: http.statusCode))
        }
        return value
    }
    private func discovery() async throws -> [String: String] {
        let result = try await object(request("https://auth.openai.com/.well-known/openid-configuration"))
        let expected = ["issuer": "https://auth.openai.com", "authorization_endpoint": "https://auth.openai.com/api/accounts/authorize", "token_endpoint": "https://auth.openai.com/api/accounts/oauth/token", "jwks_uri": "https://auth.openai.com/.well-known/jwks.json", "revocation_endpoint": "https://auth.openai.com/api/accounts/oauth/revoke"]
        guard expected.allSatisfy({ result[$0.key] as? String == $0.value }) else { throw ChatGPTError.message("ChatGPTの認証先が変更されています。アプリの更新が必要です。") }
        return expected
    }
    func status(restore: Bool = false) async throws -> [String: Any] {
        if let storageError { throw storageError }
        if restore, selected?.accessToken != nil {
            do { try await loadModels(); event(["type": "attached"]) }
            catch { event(["type": "detached", "quiet": true, "message": "接続を確認できません。もう一度ChatGPTでログインしてください。"]); throw error }
        }
        let signedIn = selected?.accessToken != nil && !modelChoices.isEmpty
        return ["authenticated": signedIn, "account": selected?.label ?? "", "models": modelChoices, "model": model,
                "accounts": vault.accounts.map { ["id": $0.clientID, "label": $0.label] }, "selectedAccount": vault.selectedClient ?? ""]
    }
    func signIn(from presenter: UIViewController, newAccount: Bool = false) async throws -> [String: Any] {
        guard loginContinuation == nil, presenter.presentedViewController == nil else { throw ChatGPTError.message("ログイン画面を閉じてから、もう一度お試しください。") }
        if let storageError { throw storageError }
        guard !newAccount || vault.accounts.count < 8 else { throw ChatGPTError.message("保存できるChatGPTアカウントは8件までです。") }
        _ = try await discovery()
        // Persist the host before opening authorization. No credentials are exposed to web content.
        try save(vault)
        stop(); pendingState = try OpenAIIdentity.random(); pendingNonce = try OpenAIIdentity.random()
        pendingVerifier = try OpenAIIdentity.random(64); pendingClient = newAccount ? nil : selected?.clientID
        loginConsuming = false; loginEpoch += 1; let attempt = loginEpoch
        return try await withCheckedThrowingContinuation { continuation in
            loginContinuation = continuation
            let receiver = OAuthLoopback(); listener = receiver
            receiver.onTarget = { [weak self] target, acknowledge in
                guard let self, self.loginContinuation != nil, !self.loginConsuming else { acknowledge(false); return }
                do {
                    let callback = try OAuthCallback.parse(target, state: self.pendingState, originalClient: self.pendingClient)
                    self.loginConsuming = true; acknowledge(true)
                    Task { do { let value = try await self.exchange(callback, attempt: attempt); self.finishLogin(.success(value), attempt: attempt) }
                           catch { self.finishLogin(.failure(error), attempt: attempt) } }
                } catch {
                    acknowledge(false)
                    // Unrelated loopback requests cannot consume a legitimate pending sign-in.
                    if target.contains("state=" + self.pendingState) { self.finishLogin(.failure(error), attempt: attempt) }
                }
            }
            do {
                try receiver.start { [weak self, weak presenter] result in
                    guard let self, self.loginContinuation != nil else { return }
                    switch result {
                    case .failure(let error): self.finishLogin(.failure(error), attempt: attempt)
                    case .success(let port):
                        guard let presenter else { self.finishLogin(.failure(ChatGPTError.message("ログイン画面を開けませんでした。")), attempt: attempt); return }
                        self.pendingRedirect = "http://127.0.0.1:\(port)/auth/callback"
                        var fields = ["client_id": self.pendingClient ?? "dynamic_agent_client", "ext_agent_host_id": self.vault.hostID,
                                      "response_type": "code", "redirect_uri": self.pendingRedirect,
                                      "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                                      "resource": "https://api.openai.com/v1", "state": self.pendingState, "nonce": self.pendingNonce,
                                      "code_challenge_method": "S256", "code_challenge": OpenAIIdentity.encode(Data(SHA256.hash(data: Data(self.pendingVerifier.utf8))))]
                        if self.pendingClient == nil { fields["agent_name_hint"] = "VOICEVOX LiveTalk" }
                        else if let hint = self.selected?.idToken { fields["id_token_hint"] = hint }
                        var url = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
                        url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
                        guard let destination = url.url else { self.finishLogin(.failure(ChatGPTError.message("ログイン画面を開けませんでした。")), attempt: attempt); return }
                        let browser = SFSafariViewController(url: destination); browser.delegate = self
                        browser.preferredControlTintColor = UIColor(red: 73/255, green: 105/255, blue: 197/255, alpha: 1)
                        self.safari = browser; presenter.present(browser, animated: true)
                    }
                }
                loginTimer = Task { try? await Task.sleep(nanoseconds: 600_000_000_000); if !Task.isCancelled { self.finishLogin(.failure(ChatGPTError.message("ログインの待ち時間を超えました。もう一度お試しください。")), attempt: attempt) } }
            } catch { finishLogin(.failure(error), attempt: attempt) }
        }
    }
    private func exchange(_ callback: OAuthCallback, attempt: Int) async throws -> [String: Any] {
        let value = try await object(request("https://auth.openai.com/api/accounts/oauth/token", form: ["grant_type": "authorization_code", "client_id": callback.clientID, "code": callback.code, "code_verifier": pendingVerifier, "redirect_uri": pendingRedirect, "resource": "https://api.openai.com/v1"]))
        guard attempt == loginEpoch, loginContinuation != nil, let token = value["id_token"] as? String else { throw ChatGPTError.message("ログインを確認できませんでした。") }
        let jwks = try await object(request("https://auth.openai.com/.well-known/jwks.json"))
        let claims = try OpenAIIdentity.verify(token: token, keys: jwks["keys"] as? [[String: Any]] ?? [], client: callback.clientID, nonce: pendingNonce)
        guard attempt == loginEpoch, let subject = claims["sub"] as? String,
              pendingClient == nil || selected?.subject == subject else { throw ChatGPTError.message("選択したChatGPTアカウントと一致しません。別のアカウントとしてログインしてください。") }
        let credential = try credential(value, client: callback.clientID, subject: subject, label: String((claims["name"] as? String ?? "ChatGPTアカウント").prefix(64)), previous: nil)
        guard vault.accounts.first(where: { $0.clientID == callback.clientID }).map({ $0.subject == subject }) ?? true else { throw ChatGPTError.message("保存した登録とアカウントが一致しません。") }
        var next = vault; next.accounts.removeAll { $0.clientID == credential.clientID && $0.subject == credential.subject }
        next.accounts.append(credential); next.selectedClient = credential.clientID; try save(next)
        history.reset(); modelChoices = []; model = ""; try await loadModels()
        guard attempt == loginEpoch else { throw CancellationError() }
        event(["type": "attached"]); return try await status()
    }
    private func finishLogin(_ result: Result<[String: Any], Error>, attempt: Int) {
        guard attempt == loginEpoch, let continuation = loginContinuation else { return }
        loginContinuation = nil; loginTimer?.cancel(); loginTimer = nil
        listener?.stop(); listener = nil; safari?.delegate = nil; safari?.dismiss(animated: true); safari = nil
        pendingState = ""; pendingNonce = ""; pendingVerifier = ""; pendingRedirect = ""; pendingClient = nil
        continuation.resume(with: result)
    }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        if !loginConsuming { finishLogin(.failure(ChatGPTError.message("cancelled")), attempt: loginEpoch) }
    }
    private func credential(_ value: [String: Any], client: String, subject: String, label: String, previous: ChatGPTCredential?) throws -> ChatGPTCredential {
        let scopes = (value["scope"] as? String)?.split(separator: " ").map(String.init) ?? previous?.scopes ?? []
        guard scopes.contains("chatgpt.tokens.use.direct"), scopes.contains("resource.invoke"),
              let access = value["access_token"] as? String, !access.isEmpty, access.count <= 65536,
              let refresh = value["refresh_token"] as? String, !refresh.isEmpty, refresh.count <= 65536,
              (value["token_type"] as? String)?.lowercased() == "bearer", let expires = value["expires_in"] as? Double,
              expires.isFinite, expires > 0, expires <= 86400 else { throw ChatGPTError.message("ChatGPTの利用枠を使う許可を確認できませんでした。ログイン時に利用枠の使用を許可してください。") }
        return ChatGPTCredential(clientID: client, subject: subject, label: label, accessToken: access, refreshToken: refresh,
                                 idToken: value["id_token"] as? String ?? previous?.idToken, expiresAt: Date().timeIntervalSince1970 + expires, scopes: scopes)
    }
    private func access() async throws -> ChatGPTCredential {
        guard let current = selected, current.accessToken != nil, let refresh = current.refreshToken else { throw ChatGPTError.message("ChatGPTにログインしてください。") }
        if current.expiresAt > Date().timeIntervalSince1970 + 90 { return current }
        if let refreshTask { return try await refreshTask.value }
        let account = current.clientID
        let work = Task { [self] () throws -> ChatGPTCredential in
            let result = try await object(request("https://auth.openai.com/api/accounts/oauth/token", form: ["grant_type": "refresh_token", "client_id": account, "refresh_token": refresh, "resource": "https://api.openai.com/v1"]))
            try Task.checkCancellation()
            guard vault.selectedClient == account, selected?.refreshToken == refresh else { throw CancellationError() }
            let updated = try credential(result, client: account, subject: current.subject, label: current.label, previous: current)
            var next = vault; guard let index = next.accounts.firstIndex(where: { $0.clientID == account }) else { throw CancellationError() }
            next.accounts[index] = updated; try save(next); return updated
        }
        refreshTask = work; defer { refreshTask = nil }; return try await work.value
    }
    private func loadModels() async throws {
        let account = try await access()
        let result = try await object(request("https://api.openai.com/v1/models", token: account.accessToken))
        guard vault.selectedClient == account.clientID else { throw CancellationError() }
        let models = (result["models"] as? [[String: Any]] ?? []).compactMap { value -> [String: String]? in
            guard value["visibility"] as? String == "list", let slug = value["slug"] as? String, !slug.isEmpty, slug.count <= 256 else { return nil }
            return ["id": slug, "label": String((value["display_name"] as? String ?? slug).prefix(100))]
        }
        guard !models.isEmpty else { throw ChatGPTError.message("このアカウントで使える会話モデルが見つかりません。ChatGPTの利用許可とプランを確認してください。") }
        modelChoices = models
        let saved = UserDefaults.standard.string(forKey: "chatgpt.model." + account.clientID) ?? ""
        model = models.contains(where: { $0["id"] == saved }) ? saved : (models.first?["id"] ?? "")
    }
    func selectModel(_ value: String) throws {
        guard modelChoices.contains(where: { $0["id"] == value }), let client = vault.selectedClient else { throw ChatGPTError.message("利用できる会話モデルを選んでください。") }
        stop(); history.reset(); model = value; UserDefaults.standard.set(value, forKey: "chatgpt.model." + client)
    }
    func selectAccount(_ value: String) async throws -> [String: Any] {
        guard vault.accounts.contains(where: { $0.clientID == value }) else { throw ChatGPTError.message("保存したChatGPTアカウントを選んでください。") }
        stop(); cancelLogin(); refreshTask?.cancel(); refreshTask = nil
        var next = vault; next.selectedClient = value; try save(next); history.reset(); modelChoices = []; model = ""
        event(["type": "detached", "quiet": true, "message": "アカウントを切り替えています。"])
        return try await status(restore: true)
    }
    func signOut() async throws -> [String: Any] {
        stop(); cancelLogin(); refreshTask?.cancel(); refreshTask = nil
        let account = selected
        var next = vault
        if let index = next.accounts.firstIndex(where: { $0.clientID == next.selectedClient }) {
            next.accounts[index].accessToken = nil; next.accounts[index].refreshToken = nil; next.accounts[index].idToken = nil; next.accounts[index].expiresAt = 0
        }
        try save(next); history.reset(); modelChoices = []; model = ""
        event(["type": "detached", "quiet": true, "message": "ログアウトしました。"])
        var remoteRevoked = false
        if let account, let refresh = account.refreshToken {
            for _ in 0..<2 {
                do { _ = try await object(request("https://auth.openai.com/api/accounts/oauth/revoke", form: ["token": refresh, "token_type_hint": "refresh_token", "client_id": account.clientID])); remoteRevoked = true; break }
                catch { try? await Task.sleep(nanoseconds: 300_000_000) }
            }
        }
        var value = try await status(); value["remoteRevoked"] = remoteRevoked; return value
    }
    func stop(heard: String? = nil, responseID: String? = nil) {
        epoch += 1; responseWatchdog?.cancel(); responseWatchdog = nil; responseTask?.cancel(); responseTask = nil
        history.interrupt(heard: heard, id: responseID)
    }
    private func cancelLogin() {
        finishLogin(.failure(ChatGPTError.message("cancelled")), attempt: loginEpoch)
        loginEpoch += 1
    }
    private func watchResponse(_ round: Int) {
        responseWatchdog?.cancel()
        responseWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled, let self, self.epoch == round else { return }
            self.stop(); self.event(["type": "error", "message": "ChatGPTの返答が止まったため会話を停止しました。通信を確認して再開してください。"])
        }
    }
    func send(_ text: String, instructions: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 12000 else { throw ChatGPTError.message("質問は12,000文字以内にしてください。") }
        let pendingEpoch = epoch
        let account = try await access()
        guard epoch == pendingEpoch, vault.selectedClient == account.clientID else { throw ChatGPTError.message("cancelled") }
        guard !model.isEmpty else { throw ChatGPTError.message("ChatGPTでログインし、会話モデルを選んでください。") }
        stop(); let round = epoch, responseID = UUID().uuidString.lowercased()
        let messages = history.begin(text, id: responseID)
        var request = request("https://api.openai.com/v1/responses", token: account.accessToken)
        request.httpMethod = "POST"; request.timeoutInterval = 90; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": messages, "instructions": instructions, "store": false, "stream": true])
        event(["type": "waiting"]); event(["type": "start", "id": responseID]); watchResponse(round)
        responseTask = Task { [self] in
            var answer = "", completed = false
            do {
                let (bytes, response) = try await session.bytes(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else { throw ChatGPTError.message("ChatGPTからの返答を確認できませんでした。") }
                if !(200..<300).contains(http.statusCode) {
                    var body = Data()
                    for try await byte in bytes { try Task.checkCancellation(); guard body.count < 65536 else { break }; body.append(byte) }
                    let value = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                    let code = (value["error"] as? [String: Any])?["code"] as? String
                    throw ChatGPTError.message(PlanUsageError.text(code: code, status: http.statusCode))
                }
                var decoder = SSEDecoder()
                for try await byte in bytes {
                    try Task.checkCancellation(); guard round == epoch else { return }
                    guard let data = try decoder.byte(byte), data != "[DONE]", let raw = data.data(using: .utf8), let value = try JSONSerialization.jsonObject(with: raw) as? [String: Any], let type = value["type"] as? String else { continue }
                    if type == "response.output_text.delta", let delta = value["delta"] as? String {
                        watchResponse(round)
                        answer += delta; guard answer.utf16.count <= 12000 else { throw ChatGPTError.message("返答が長すぎるため停止しました。短く答えるよう、もう一度話しかけてください。") }
                        history.update(answer, id: responseID)
                        event(["type": "snapshot", "id": responseID, "text": answer, "done": false])
                    } else if type == "response.completed" {
                        completed = true; break
                    } else if ["response.failed", "response.incomplete", "error"].contains(type) {
                        let response = value["response"] as? [String: Any], failure = response?["error"] as? [String: Any] ?? value["error"] as? [String: Any]
                        throw ChatGPTError.message(PlanUsageError.text(code: failure?["code"] as? String ?? value["code"] as? String))
                    }
                }
                try Task.checkCancellation(); guard round == epoch else { return }
                guard completed, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ChatGPTError.message("ChatGPTの返答が途中で切れました。会話を再開してください。") }
                history.update(answer, id: responseID)
                responseWatchdog?.cancel(); responseWatchdog = nil
                event(["type": "snapshot", "id": responseID, "text": answer, "done": true]); responseTask = nil
            } catch {
                guard round == epoch, !Task.isCancelled else { return }
                responseTask = nil; responseWatchdog?.cancel(); responseWatchdog = nil
                event(["type": "error", "message": (error as? ChatGPTError)?.localizedDescription ?? "ChatGPTに接続できませんでした。通信を確認して会話を再開してください。"])
            }
        }
    }
}
