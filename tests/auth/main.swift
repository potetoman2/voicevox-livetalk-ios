import Foundation
import Security
var passed = 0
func check(_ value: Bool, _ label: String) { precondition(value, label); passed += 1 }
func rejects(_ label: String, _ work: () throws -> Void) { do { try work(); fatalError(label) } catch { passed += 1 } }
let callback = try OAuthCallback.parse("/auth/callback?state=abc&code=code%2Bvalue&client_id=oaiapp_fixture", state: "abc", originalClient: nil)
check(callback.code == "code+value", "one decode")
rejects("wrong state") { _ = try OAuthCallback.parse("/auth/callback?state=bad&code=x&client_id=oaiapp_fixture", state: "abc", originalClient: nil) }
rejects("missing issued client") { _ = try OAuthCallback.parse("/auth/callback?state=abc&code=x", state: "abc", originalClient: nil) }
rejects("duplicate state") { _ = try OAuthCallback.parse("/auth/callback?state=abc&state=abc&code=x&client_id=oaiapp_fixture", state: "abc", originalClient: nil) }
rejects("returning account swap") { _ = try OAuthCallback.parse("/auth/callback?state=abc&code=x&client_id=oaiapp_other", state: "abc", originalClient: "oaiapp_fixture") }
rejects("declined permission") { _ = try OAuthCallback.parse("/auth/callback?state=abc&error=access_denied", state: "abc", originalClient: nil) }
rejects("wrong path") { _ = try OAuthCallback.parse("/callback?state=abc&code=x&client_id=oaiapp_fixture", state: "abc", originalClient: nil) }
check(try OAuthCallback.parse("/auth/callback?state=abc&code=x", state: "abc", originalClient: "oaiapp_fixture").clientID == "oaiapp_fixture", "reuse issued client")
var decoder = SSEDecoder()
check(try decoder.line(": heartbeat") == nil, "ignore heartbeat")
check(try decoder.line("data: {\"type\":") == nil, "buffer data")
check(try decoder.line("data: \"response.completed\"}") == nil, "multiline data")
check(try decoder.line("") == "{\"type\":\n\"response.completed\"}", "complete frame")
rejects("bounded event") { var d = SSEDecoder(); _ = try d.line("data: " + String(repeating: "x", count: 262145)) }
rejects("empty data lines cannot grow without limit") {
    var d = SSEDecoder(); for _ in 0..<4097 { _ = try d.line("data:") }
}
rejects("joined separators count toward event byte limit") {
    var d = SSEDecoder(); _ = try d.line("data: " + String(repeating: "x", count: 262144)); _ = try d.line("data:")
}
var boundary = SSEDecoder()
_ = try boundary.line("data: " + String(repeating: "x", count: 262143))
_ = try boundary.line("data:")
check(try boundary.line("")?.utf8.count == 262144, "exact event byte limit remains valid")
_ = try boundary.line("data: next")
check(try boundary.line("") == "next", "event byte and line budgets reset after delivery")
var emptyLines = SSEDecoder()
for _ in 0..<4096 { _ = try emptyLines.line("data:") }
check(try emptyLines.line("") == String(repeating: "\n", count: 4095), "bounded empty data lines preserve SSE semantics")
check(PlanUsageError.text(code: "subscription_sharing_usage_limit_exceeded").contains("利用上限"), "usage recovery")
for ending in ["\n", "\r\n", "\r"] {
    var stream = SSEDecoder(), received = [String]()
    let wire = ": heartbeat" + ending + "data: こんにちは🙂" + ending + ending + "data: done" + ending + ending
    for byte in wire.utf8 { if let frame = try stream.byte(byte) { received.append(frame) } }
    check(received == ["こんにちは🙂", "done"], "byte stream preserves Unicode and blank frames: \(ending.debugDescription)")
}
rejects("bounded partial line") { var d = SSEDecoder(); for _ in 0..<262151 { _ = try d.byte(120) } }
rejects("invalid UTF8") { var d = SSEDecoder(); _ = try d.byte(255); _ = try d.byte(10) }
var memory = ConversationMemory()
check(memory.begin("first question", id: "first").count == 1, "remember current question")
memory.update("heard part and unsaid tail", id: "first")
memory.interrupt(heard: "heard part", id: "first")
check(memory.messages.last?["content"] == "heard part", "trim in-progress answer to heard words")
check(memory.begin("follow up", id: "second").map { $0["content"]! } == ["first question", "heard part", "follow up"], "keep interrupted conversation context")
memory.update("next answer", id: "second")
memory.update("stale answer", id: "first")
memory.interrupt(heard: "stale", id: "first")
check(memory.messages.last?["content"] == "next answer", "ignore old answer and old interruption")
memory.interrupt(heard: "", id: "second")
check(memory.messages.last?["role"] == "user", "do not remember unheard answer")
for i in 0..<30 { _ = memory.begin("q\(i)", id: "r\(i)"); memory.update("a\(i)", id: "r\(i)") }
check(memory.messages.count == 12, "bounded conversation history")
memory.reset(); check(memory.messages.isEmpty, "account change resets conversation")

// Create a temporary test key in memory. No developer/user credentials are used.
let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
let publicKey = SecKeyCopyPublicKey(privateKey)!
let der = Array(SecKeyCopyExternalRepresentation(publicKey, nil)! as Data)
var offset = 0
func item() -> (UInt8, [UInt8]) {
    let tag = der[offset]; offset += 1
    var count = Int(der[offset]); offset += 1
    if count >= 128 { let lengthBytes = count - 128; count = 0; for _ in 0..<lengthBytes { count = count * 256 + Int(der[offset]); offset += 1 } }
    let bytes = Array(der[offset..<offset+count]); offset += count; return (tag, bytes)
}
_ = der[offset]; offset += 1
let sequenceLength = Int(der[offset]); offset += 1
if sequenceLength >= 128 { offset += sequenceLength - 128 }
let modulus = item().1.drop(while: { $0 == 0 }), exponent = item().1
let jwk: [String: Any] = ["kid":"fixture", "kty":"RSA", "alg":"RS256", "use":"sig", "n":OpenAIIdentity.encode(Data(modulus)), "e":OpenAIIdentity.encode(Data(exponent))]
let header = OpenAIIdentity.encode(try JSONSerialization.data(withJSONObject: ["alg":"RS256","kid":"fixture"]))
let claims: [String: Any] = ["iss":"https://auth.openai.com","aud":"oaiapp_fixture","sub":"test-subject","nonce":"test-nonce","iat":1000.0,"exp":2000.0]
func token(_ value: [String: Any]) throws -> String {
    let body = OpenAIIdentity.encode(try JSONSerialization.data(withJSONObject: value)), message = header + "." + body
    let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data(message.utf8) as CFData, nil)! as Data
    return message + "." + OpenAIIdentity.encode(signature)
}
let valid = try token(claims)
check(try OpenAIIdentity.verify(token: valid, keys: [jwk], client: "oaiapp_fixture", nonce: "test-nonce", now: 1500)["sub"] as? String == "test-subject", "verified RSA signature and identity")
rejects("wrong nonce") { _ = try OpenAIIdentity.verify(token: valid, keys: [jwk], client: "oaiapp_fixture", nonce: "bad", now: 1500) }
rejects("wrong audience") { _ = try OpenAIIdentity.verify(token: valid, keys: [jwk], client: "oaiapp_other", nonce: "test-nonce", now: 1500) }
rejects("expired") { _ = try OpenAIIdentity.verify(token: valid, keys: [jwk], client: "oaiapp_fixture", nonce: "test-nonce", now: 2500) }
rejects("tampered signature") { _ = try OpenAIIdentity.verify(token: valid + "x", keys: [jwk], client: "oaiapp_fixture", nonce: "test-nonce", now: 1500) }
var wrongIssuer = claims; wrongIssuer["iss"] = "https://untrusted.example"
rejects("wrong issuer despite valid signature") { _ = try OpenAIIdentity.verify(token: try token(wrongIssuer), keys: [jwk], client: "oaiapp_fixture", nonce: "test-nonce", now: 1500) }
print("OAuth / SSE / RSA identity: \(passed) assertions passed")
