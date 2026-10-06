import Foundation
import Network

/// The OAuth callback listens only on this phone's loopback address and expires after ten minutes.
final class OAuthLoopback {
    private var listener: NWListener?
    private var connections = [NWConnection]()
    var onTarget: ((String, @escaping (Bool) -> Void) -> Void)?
    func start(_ completion: @escaping (Result<UInt16, Error>) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters, on: .any)
        self.listener = listener
        var reported = false
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: if !reported, let port = listener.port { reported = true; completion(.success(port.rawValue)) }
            case .failed: if !reported { reported = true; completion(.failure(ChatGPTError.message("ログインの戻り先を準備できませんでした。"))) }
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, self.connections.count < 8 else { connection.cancel(); return }
            self.connections.append(connection); connection.start(queue: .main)
            self.read(connection, accumulated: Data())
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel(); self.connections.removeAll { $0 === connection } }
        }
        listener.start(queue: .main)
    }
    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let bytes = accumulated + (data ?? Data())
            guard bytes.count <= 16384 else { self.respond(connection, accepted: false); return }
            if let request = String(data: bytes, encoding: .utf8), request.contains("\r\n\r\n") {
                let first = request.components(separatedBy: "\r\n").first?.split(separator: " ").map(String.init) ?? []
                guard first.count == 3, first[0] == "GET", first[1].hasPrefix("/auth/callback?"), first[2].hasPrefix("HTTP/1.") else { self.respond(connection, accepted: false); return }
                self.onTarget?(first[1]) { [weak self] accepted in self?.respond(connection, accepted: accepted) }
            } else if !complete && error == nil { self.read(connection, accumulated: bytes) }
            else { connection.cancel() }
        }
    }
    private func respond(_ connection: NWConnection, accepted: Bool) {
        let body = "<!doctype html><html lang=ja><meta charset=utf-8><meta name=viewport content='width=device-width'><title>LiveTalk</title><body><h2>" + (accepted ? "ログインを受け付けました" : "確認できませんでした") + "</h2><p>この画面を閉じてLiveTalkに戻ってください。</p></body></html>"
        let head = "HTTP/1.1 \(accepted ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; base-uri 'none'; frame-ancestors 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    func stop() { listener?.cancel(); listener = nil; connections.forEach { $0.cancel() }; connections = []; onTarget = nil }
}
