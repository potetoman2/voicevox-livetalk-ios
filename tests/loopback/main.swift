import Foundation
import Network

Task { @MainActor in
    do {
        let receiver = OAuthLoopback()
        var callbacks = 0
        receiver.onTarget = { target, acknowledge in
            do {
                let value = try OAuthCallback.parse(target, state: "fixture-state", originalClient: nil)
                precondition(value.code == "fixture-code")
                callbacks += 1; acknowledge(true)
            } catch { acknowledge(false) }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            do { try receiver.start { continuation.resume(with: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        precondition(port > 0)
        let session = URLSession(configuration: .ephemeral)
        let base = "http://127.0.0.1:\(port)"
        let (_, rejected) = try await session.data(from: URL(string: base + "/unrelated")!)
        precondition((rejected as? HTTPURLResponse)?.statusCode == 400 && callbacks == 0)
        let (_, invalid) = try await session.data(from: URL(string: base + "/auth/callback?state=wrong&code=x&client_id=oaiapp_fixture")!)
        precondition((invalid as? HTTPURLResponse)?.statusCode == 400 && callbacks == 0)
        let (body, accepted) = try await session.data(from: URL(string: base + "/auth/callback?state=fixture-state&code=fixture-code&client_id=oaiapp_fixture")!)
        precondition((accepted as? HTTPURLResponse)?.statusCode == 200 && callbacks == 1)
        let page = String(data: body, encoding: .utf8)!
        precondition(!page.contains("fixture-code") && !page.contains("fixture-state"))
        precondition((accepted as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        receiver.stop(); session.invalidateAndCancel()
        print("Real HTTP loopback callback: 6 assertions passed")
        exit(0)
    } catch { fputs("Loopback check failed: \(error)\n", stderr); exit(1) }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fputs("Loopback check timed out\n", stderr); exit(1) }
dispatchMain()
