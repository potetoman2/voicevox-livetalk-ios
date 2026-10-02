import UIKit
import WebKit
import AVFoundation
import AudioToolbox
import Speech
import UniformTypeIdentifiers

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var owner: LiveTalkController?
    init(_ owner: LiveTalkController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

final class LiveTalkController: UIViewController, WKNavigationDelegate, AVAudioPlayerDelegate, UIDocumentPickerDelegate {
    private var app: WKWebView!
    private var chat: WKWebView!
    private var chatPanel: UIStackView!
    private let core = VoiceCore()
    private var generation = 0
    private var loaded = false
    private var foreground = true
    private var player: AVAudioPlayer?
    private var playId: Int?
    private var playingFile: URL?
    private var documentId: Int?
    private var chatRequests = Set<Int>()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var speechTask: SFSpeechRecognitionTask?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionRound = 0
    private var listening = false
    private var tapInstalled = false
    private var speechTimeout: DispatchWorkItem?
    private let defaults = UserDefaults.standard
    private var waves: URL { FileManager.default.temporaryDirectory.appendingPathComponent("livetalk-waves", isDirectory: true) }

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        try? FileManager.default.createDirectory(at: waves, withIntermediateDirectories: true)
        cleanWaves()
        let local = WKWebViewConfiguration()
        local.userContentController.add(WeakHandler(self), name: "native")
        app = WKWebView(frame: .zero, configuration: local); app.navigationDelegate = self
        let remote = WKWebViewConfiguration()
        remote.userContentController.add(WeakHandler(self), name: "chatEvent")
        remote.websiteDataStore = .default()
        if let shared = Bundle.main.resourceURL?.appendingPathComponent("shared"),
           let dom = try? String(contentsOf: shared.appendingPathComponent("dom.js"), encoding: .utf8),
           let bridge = try? String(contentsOf: shared.appendingPathComponent("chat-bridge.js"), encoding: .utf8) {
            remote.userContentController.addUserScript(WKUserScript(source: "if(location.hostname==='chatgpt.com'){" + dom + bridge + "}", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        chat = WKWebView(frame: .zero, configuration: remote); chat.navigationDelegate = self
        let toolbar = UIStackView(); toolbar.axis = .horizontal; toolbar.distribution = .fillEqually
        let back = UIButton(type: .system); back.setTitle("通話に戻る", for: .normal); back.addTarget(self, action: #selector(closeChat), for: .touchUpInside)
        let attach = UIButton(type: .system); attach.setTitle("このチャットで通話", for: .normal); attach.addTarget(self, action: #selector(attachChat), for: .touchUpInside)
        toolbar.addArrangedSubview(back); toolbar.addArrangedSubview(attach); toolbar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        chatPanel = UIStackView(arrangedSubviews: [toolbar, chat]); chatPanel.axis = .vertical
        for web in [app!, chatPanel!] as [UIView] {
            web.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(web)
            NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor), web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        }
        chatPanel.isHidden = true
        if let shared = Bundle.main.resourceURL?.appendingPathComponent("shared") { app.loadFileURL(shared.appendingPathComponent("index.html"), allowingReadAccessTo: shared) }
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func js(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let text = String(data: data, encoding: .utf8) else { return "null" }; return text }
    private func reply(_ id: Int, _ result: Any? = nil, _ error: String? = nil) {
        DispatchQueue.main.async { [weak self] in guard let self, self.loaded else { return }; self.app.evaluateJavaScript("window.LiveTalkReply(\(id),\(self.js(result ?? NSNull())),\(self.js(error as Any? ?? NSNull())))", completionHandler: nil) }
    }
    private func event(_ value: [String: Any]) { if loaded { app.evaluateJavaScript("window.LiveTalkEvent(\(js(value)))", completionHandler: nil) } }
    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if message.name == "chatEvent" {
            guard message.frameInfo.request.url?.host == "chatgpt.com", chat.url?.scheme == "https", chat.url?.host == "chatgpt.com", let e = message.body as? [String: Any] else { return }
            if e["type"] as? String == "ack", let id = e["id"] as? Int, chatRequests.remove(id) != nil { reply(id, true, e["error"] as? String) }
            else { event(e) }
            return
        }
        guard message.name == "native", message.frameInfo.request.url?.isFileURL == true,
              let raw = message.body as? String, let data = raw.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = m["id"] as? Int, let command = m["command"] as? String else { return }
        loaded = true
        handle(id, command, (m["args"] as? [String: Any]) ?? [:])
    }
    private func handle(_ id: Int, _ command: String, _ args: [String: Any]) {
        switch command {
        case "loadSettings":
            let data = defaults.data(forKey: "settings")
            reply(id, data.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:])
        case "saveSettings": do { defaults.set(try JSONSerialization.data(withJSONObject: args["settings"] ?? [:]), forKey: "settings"); reply(id, true) } catch { reply(id, nil, error.localizedDescription) }
        case "init": prepare(id, interactive: (args["interactive"] as? Bool) ?? false)
        case "synthesize": synthesize(id, args)
        case "play": play(id, args)
        case "stop": generation = (args["generation"] as? Int) ?? (generation + 1); stopPlayer(); cleanWaves(); reply(id, true)
        case "discard": if let name = args["file"] as? String, let url = audioFile(name) { try? FileManager.default.removeItem(at: url) }; reply(id, true)
        case "asrStart": startRecognition(id, headset: (args["headset"] as? Bool) ?? false)
        case "asrStop": stopRecognition(); reply(id, true)
        case "chatOpen": chatPanel.isHidden = false; if chat.url == nil { chat.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }; reply(id, true)
        case "chatSend": chatCommand(id, method: "send", text: (args["text"] as? String) ?? "")
        case "chatStop": if chat.url?.host == "chatgpt.com" { chatCommand(id, method: "stop", text: "") } else { reply(id, true) }
        case "copy": UIPasteboard.general.string = args["text"] as? String; reply(id, true)
        case "paste": reply(id, UIPasteboard.general.string ?? "")
        case "exportSettings": export(id, settings: args["settings"] ?? [:])
        case "importSettings": if documentId != nil { reply(id, nil, "ファイル選択中です"); return }; documentId = id; let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true); picker.delegate = self; present(picker, animated: true)
        case "cue": AudioServicesPlaySystemSound(1104); reply(id, true)
        default: reply(id, nil, "未対応の操作です")
        }
    }
    private func prepare(_ id: Int, interactive: Bool) {
        if !defaults.bool(forKey: "voiceTerms") {
            guard interactive else { reply(id, nil, "「音声を準備」から利用条件を確認してください"); return }
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("voice/NOTICE.txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { reply(id, nil, "音声モデルが同梱されていません"); return }
            let alert = UIAlertController(title: "音声モデルの利用条件", message: text, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "同意しない", style: .cancel) { _ in self.reply(id, nil, "利用条件への同意が必要です") })
            alert.addAction(UIAlertAction(title: "確認して同意する", style: .default) { _ in self.defaults.set(true, forKey: "voiceTerms"); self.prepare(id, interactive: false) }); present(alert, animated: true); return
        }
        core.prepare { [weak self] result in guard let self else { return }; switch result {
        case .success(let styles): self.reply(id, ["styles": styles, "platform": "iOS", "asrAvailable": self.recognizer?.supportsOnDeviceRecognition ?? false])
        case .failure(let error): self.reply(id, nil, "VOICEVOXを準備できませんでした: " + error.localizedDescription)
        } }
    }
    private func synthesize(_ id: Int, _ args: [String: Any]) {
        guard let gen = args["generation"] as? Int, gen == generation, foreground else { reply(id, nil, "cancelled"); return }
        core.synthesize(text: (args["text"] as? String) ?? "", settings: (args["settings"] as? [String: Any]) ?? [:]) { [weak self] result in
            guard let self else { return }; guard gen == self.generation, self.foreground else { self.reply(id, nil, "cancelled"); return }
            switch result {
            case .success(let data): do { let name = UUID().uuidString.lowercased() + ".wav"; try data.write(to: self.waves.appendingPathComponent(name), options: .atomic); self.reply(id, name) } catch { self.reply(id, nil, error.localizedDescription) }
            case .failure(let error): self.reply(id, nil, error.localizedDescription)
            }
        }
    }
    private func audioFile(_ name: String) -> URL? { guard name.range(of: "^[a-f0-9-]{36}\\.wav$", options: .regularExpression) != nil else { return nil }; return waves.appendingPathComponent(name) }
    private func play(_ id: Int, _ args: [String: Any]) {
        guard foreground, args["generation"] as? Int == generation, let name = args["file"] as? String, let url = audioFile(name) else { reply(id, nil, "cancelled"); return }
        do {
            stopPlayer(); try audioSession()
            player = try AVAudioPlayer(contentsOf: url); playId = id; playingFile = url; player?.delegate = self; player?.prepareToPlay()
            if player?.play() != true { throw MobileError.message("音声を再生できません") }
        } catch { playId = nil; stopPlayer(); reply(id, nil, error.localizedDescription) }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }; let id = playId; self.player = nil; playId = nil
        if let file = playingFile { try? FileManager.default.removeItem(at: file) }; playingFile = nil
        if let id { reply(id, true, flag ? nil : "音声の再生が中断されました") }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { guard player === self.player else { return }; let id = playId; playId = nil; stopPlayer(); if let id { reply(id, nil, error?.localizedDescription ?? "音声を再生できません") } }
    private func stopPlayer() { player?.stop(); player = nil; if let id = playId { reply(id, nil, "cancelled") }; playId = nil; if let file = playingFile { try? FileManager.default.removeItem(at: file) }; playingFile = nil }
    private func cleanWaves() { if let files = try? FileManager.default.contentsOfDirectory(at: waves, includingPropertiesForKeys: nil) { for file in files { try? FileManager.default.removeItem(at: file) } } }
    private func audioSession() throws { let session = AVAudioSession.sharedInstance(); try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]); try session.setActive(true) }
    private func hasHeadset() -> Bool { AVAudioSession.sharedInstance().currentRoute.outputs.contains { [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) } }
    private func startRecognition(_ id: Int, headset: Bool) {
        guard foreground else { reply(id, nil, "画面を開いてから話しかけてください"); return }
        guard recognizer?.supportsOnDeviceRecognition == true else { reply(id, nil, "端末内の日本語音声認識に対応していません。文字入力をご利用ください"); return }
        if headset && !hasHeadset() { reply(id, nil, "イヤホンを接続するか、イヤホン設定を解除してください"); return }
        let permissionRound = recognitionRound
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { guard let self else { return }; guard status == .authorized else { self.reply(id, nil, "音声認識が許可されていません"); return }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in DispatchQueue.main.async { guard let self else { return }; guard permissionRound == self.recognitionRound else { self.reply(id, nil, "cancelled"); return }; if allowed { self.beginRecognition(id) } else { self.reply(id, nil, "マイクが許可されていません") } } }
            }
        }
    }
    private func beginRecognition(_ id: Int) {
        guard foreground else { reply(id, nil, "cancelled"); return }
        do {
            stopRecognition(); try audioSession()
            guard let recognizer, recognizer.isAvailable else { throw MobileError.message("音声認識を利用できません。日本語の端末内音声認識を確認してください") }
            let round = recognitionRound; let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            speechRequest = request; listening = true
            let input = audioEngine.inputNode; let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MobileError.message("マイクを利用できません") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }; tapInstalled = true
            speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async { guard let self, self.listening, round == self.recognitionRound else { return }
                    if let result { let text = result.bestTranscription.formattedString
                        if result.isFinal { self.stopRecognition(); self.event(["type": "asrFinal", "text": text]) }
                        else { self.event(["type": "partial", "text": text]); self.scheduleSpeechEnd(round) }
                    }
                    if let error, self.listening { self.stopRecognition(); self.event(["type": "asrError", "message": "音声認識が停止しました: " + error.localizedDescription]) }
                }
            }
            audioEngine.prepare(); try audioEngine.start(); reply(id, true)
            let timeout = DispatchWorkItem { [weak self] in guard let self, self.listening, round == self.recognitionRound else { return }; self.stopRecognition(); self.event(["type": "asrIdle"]) }; speechTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
        } catch { stopRecognition(); reply(id, nil, error.localizedDescription) }
    }
    private func scheduleSpeechEnd(_ round: Int) {
        speechTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.listening, round == self.recognitionRound else { return }
            self.audioEngine.stop()
            if self.tapInstalled { self.audioEngine.inputNode.removeTap(onBus: 0); self.tapInstalled = false }
            self.speechRequest?.endAudio()
            let finalTimeout = DispatchWorkItem { [weak self] in
                guard let self, self.listening, round == self.recognitionRound else { return }
                self.stopRecognition(); self.event(["type": "asrError", "message": "認識結果を確定できませんでした。もう一度話しかけてください"])
            }
            self.speechTimeout = finalTimeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: finalTimeout)
        }
        speechTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: timeout)
    }
    private func stopRecognition() { listening = false; recognitionRound += 1; speechTimeout?.cancel(); speechTimeout = nil; audioEngine.stop(); if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }; speechRequest?.endAudio(); speechTask?.cancel(); speechTask = nil; speechRequest = nil }
    @objc private func closeChat() { chatPanel.isHidden = true }
    @objc private func attachChat() {
        guard chat.url?.host == "chatgpt.com" else { return }
        chat.evaluateJavaScript("window.LiveTalkMobileChat ? (LiveTalkMobileChat.arm(),true) : false") { [weak self] result, _ in
            guard let self else { return }; if result as? Bool == true { self.chatPanel.isHidden = true } else { self.notice("ChatGPTの読み込みを待って再試行してください。ログインできない場合は外部ChatGPTアプリの返答をコピーして貼り付けられます。") }
        }
    }
    private func notice(_ text: String) { let alert = UIAlertController(title: "確認", message: text, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true) }
    private func chatCommand(_ id: Int, method: String, text: String) {
        guard chat.url?.host == "chatgpt.com", chat.url?.scheme == "https" else { reply(id, nil, "ChatGPTを開いて、使うチャットを接続してください"); return }
        chatRequests.insert(id)
        chat.evaluateJavaScript("(async()=>{try{if(!window.LiveTalkMobileChat)throw Error('ChatGPTを接続してください');await LiveTalkMobileChat.\(method)(\(js(text)));window.webkit.messageHandlers.chatEvent.postMessage({type:'ack',id:\(id)});}catch(e){window.webkit.messageHandlers.chatEvent.postMessage({type:'ack',id:\(id),error:e.message});}})()", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in guard let self, self.chatRequests.remove(id) != nil else { return }; self.reply(id, nil, "ChatGPTの操作を確認できませんでした。ChatGPT画面を確認してください") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if webView === app { loaded = true } }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { if webView === chat { event(["type": "detached", "message": "ChatGPTを開きました。使うチャットで接続してください"]) } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if webView === app { decisionHandler(url.isFileURL ? .allow : .cancel); return }
        let host = url.host ?? ""
        if url.scheme == "https" && (host == "chatgpt.com" || host == "auth.openai.com" || host == "auth0.openai.com" || host.hasSuffix(".auth.openai.com")) { decisionHandler(.allow) }
        else { decisionHandler(.cancel); if action.targetFrame?.isMainFrame != false && url.scheme == "https" { UIApplication.shared.open(url) } }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === chat { event(["type": "detached", "message": "ChatGPT画面が終了しました。開き直して接続してください"]) }; webView.reload() }
    private func export(_ id: Int, settings: Any) { do {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("livetalk-settings.json"); try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil); sheet.popoverPresentationController?.sourceView = view; sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 20, width: 1, height: 1); present(sheet, animated: true); reply(id, true)
    } catch { reply(id, nil, error.localizedDescription) } }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = documentId else { return }; documentId = nil
        do { guard let url = urls.first else { throw MobileError.message("cancelled") }; let accessing = url.startAccessingSecurityScopedResource(); defer { if accessing { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); if data.count > 65536 { throw MobileError.message("設定ファイルが大きすぎます") }; reply(id, try JSONSerialization.jsonObject(with: data)) } catch { reply(id, nil, error.localizedDescription) }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { if let id = documentId { reply(id, nil, "cancelled") }; documentId = nil }
    @objc private func background() { foreground = false; generation += 1; stopRecognition(); stopPlayer(); event(["type": "background"]) }
    @objc private func resume() { foreground = true; event(["type": "foreground"]) }
    @objc private func audioInterrupted(_ notification: Notification) { if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { stopRecognition(); stopPlayer(); event(["type": "background"]); event(["type": "foreground"]) } }
}
