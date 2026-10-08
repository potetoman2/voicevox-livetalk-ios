import AVFoundation
import Speech

// CarPlay audio runs natively; it does not depend on background WebKit timers.
@MainActor
final class CarConversation: NSObject {
    var onState: (String) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }
    private let runtime = ConversationRuntime.shared
    private lazy var waitingVoice = WaitingVoice(core: runtime.core) { try AVAudioSession.sharedInstance().setActive(true) }
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var speech: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var player: AVAudioPlayer?
    private var playerDelegate: AudioPlaybackDelegate?
    private var playbackID: UUID?
    private var playerText = ""
    private var prepared: (String, Data)?
    private var transcript = "", answer = "", heard = "", responseID = ""
    private var chunks = VoiceChunkBuffer(), queue = [String]()
    private var detector = SpeechTurnDetector(silence: 0.5)
    private var timer: Task<Void, Never>?, idle: Task<Void, Never>?, startTask: Task<Void, Never>?
    private var active = false, recording = false, tapped = false, ending = false, done = false, synthesizing = false
    private var epoch = 0, micRound = 0
    private var settings = [String: Any]()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeLost), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func interrupted(_ notification: Notification) {
        if active, notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt == AVAudioSession.InterruptionType.began.rawValue { fail("電話などで音声が中断されました。会話を再開してください。") }
    }
    @objc private func routeLost(_ notification: Notification) {
        if active, notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { fail("車の音声接続が外れたため停止しました。") }
    }
    func start() {
        guard !active else { return }
        active = true; epoch += 1; let round = epoch; runtime.takeCar(self); onState("preparing")
        startTask = Task {
            do {
                guard DistributionPolicy.planUsageAllowed(requested: Bundle.main.object(forInfoDictionaryKey: "LTPlanUsageEnabled") as? Bool == true, storeBuild: Bundle.main.object(forInfoDictionaryKey: "LTCommerceEnabled") as? Bool == true) else { throw MobileError.message("この配布版ではChatGPT連携を利用できません。") }
                guard DataConsent.accepted() else { throw MobileError.message("先にiPhoneでChatGPTへ送る内容を確認し、接続してください。") }
                guard !runtime.gpt.isSigningIn else { throw MobileError.message("iPhoneでログインを完了してから会話を始めてください。") }
                guard UserDefaults.standard.string(forKey: "voiceTermsVersion") == "0.16.0:model0:2" else { throw MobileError.message("先にiPhoneで音声を準備してください。") }
                guard SFSpeechRecognizer.authorizationStatus() == .authorized, AVAudioSession.sharedInstance().recordPermission == .granted,
                      recognizer?.supportsOnDeviceRecognition == true else { throw MobileError.message("先にiPhoneでマイクと日本語音声認識を許可してください。") }
                let status = try await runtime.gpt.status(restore: true)
                guard active, round == epoch else { return }
                guard status["authenticated"] as? Bool == true else { throw MobileError.message("先にiPhoneでChatGPTにログインしてください。") }
                if let data = UserDefaults.standard.data(forKey: "settings"), let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { settings = saved }
                let styles: [[String: Any]] = try await withCheckedThrowingContinuation { continuation in runtime.core.prepare { continuation.resume(with: $0) } }
                guard active, round == epoch else { return }
                let ids = styles.flatMap { $0["styles"] as? [[String: Any]] ?? [] }.compactMap { $0["id"] as? Int }
                if !ids.contains(settings["style"] as? Int ?? 3) { settings["style"] = ids.first ?? 3 }
                if settings["feedback"] as? Bool != false { waitingVoice.warm(settings) }
                try listen()
            } catch { if active, round == epoch { fail(error.localizedDescription) } }
        }
    }
    func stop() {
        guard active else { return }; active = false; epoch += 1
        startTask?.cancel(); startTask = nil; timer?.cancel(); idle?.cancel(); waitingVoice.stop(); stopMic()
        runtime.gpt.stop(heard: heard, responseID: responseID)
        playbackID = nil; player?.stop(); player = nil; playerDelegate = nil; queue = []; prepared = nil; synthesizing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        runtime.releaseCar(self); onState("idle")
    }
    func interrupt() {
        guard active else { start(); return }
        epoch += 1; timer?.cancel(); idle?.cancel(); waitingVoice.stop(); stopMic()
        runtime.gpt.stop(heard: heard, responseID: responseID)
        playbackID = nil; player?.stop(); player = nil; playerDelegate = nil; queue = []; prepared = nil; synthesizing = false; answer = ""; heard = ""; responseID = ""
        do { try listen() } catch { fail(error.localizedDescription) }
    }
    func receive(_ event: [String: Any]) {
        guard active else { return }
        let type = event["type"] as? String ?? ""
        if type == "start" { responseID = event["id"] as? String ?? ""; answer = ""; heard = ""; chunks.reset(); queue = []; done = false; onState("thinking") }
        if type == "phase", event["id"] as? String == responseID { onState("searching"); waitingVoice.searching(token: epoch) }
        if type == "sources" { runtime.lastCarSources = event["sources"] as? [[String: String]] ?? [] }
        if type == "error" { fail(event["message"] as? String ?? "接続を確認してください。"); return }
        if type == "snapshot", event["id"] as? String == responseID {
            if !(event["text"] as? String ?? "").isEmpty { waitingVoice.stop() }
            answer = event["text"] as? String ?? ""; runtime.lastCarAnswer = VoiceChunkBuffer.clean(answer)
            done = event["done"] as? Bool == true; fill()
            idle?.cancel(); let round = epoch
            if !done { idle = Task { try? await Task.sleep(nanoseconds: 180_000_000); guard !Task.isCancelled, active, round == epoch else { return }; fill(flush: true) } }
        }
    }
    private func fill(flush: Bool = false) {
        while queue.count < 3, let chunk = chunks.take(answer, done: done, flush: flush) { if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { queue.append(chunk) } }
        pump()
    }
    private func pump() {
        guard active else { return }
        if player != nil { prefetch(); return }
        if let cached = prepared { prepared = nil; play(cached.1, text: cached.0); return }
        guard !synthesizing else { return }
        if queue.isEmpty {
            if done { onState("listening"); let round = epoch; timer?.cancel(); timer = Task { try? await Task.sleep(nanoseconds: 420_000_000); guard !Task.isCancelled, active, round == epoch else { return }; do { try listen() } catch { fail(error.localizedDescription) } } }
            return
        }
        synthesizing = true; let text = queue.removeFirst(), round = epoch
        runtime.core.synthesize(text: text, settings: settings) { [weak self] result in
            guard let self, self.active, round == self.epoch else { return }; self.synthesizing = false
            do {
                self.play(try result.get(), text: text)
            } catch { self.fail(error.localizedDescription) }
        }
    }
    private func prefetch() {
        guard active, prepared == nil, !synthesizing, !queue.isEmpty else { return }
        synthesizing = true; let text = queue.removeFirst(), round = epoch
        runtime.core.synthesize(text: text, settings: settings) { [weak self] result in
            guard let self, self.active, round == self.epoch else { return }; self.synthesizing = false
            do { self.prepared = (text, try result.get()); if self.player == nil { self.pump() } }
            catch { self.fail(error.localizedDescription) }
        }
    }
    private func play(_ wav: Data, text: String) {
        do {
            waitingVoice.stop()
            let player = try AVAudioPlayer(data: wav), id = UUID()
            let delegate = AudioPlaybackDelegate { [weak self] success in self?.playbackFinished(id: id, successfully: success) }
            playbackID = id; playerDelegate = delegate; self.player = player; playerText = text; player.delegate = delegate; player.prepareToPlay()
            guard player.play() else { throw MobileError.message("車の音声出力を確認してください。") }
            onState("speaking"); prefetch()
        } catch { fail(error.localizedDescription) }
    }
    private func playbackFinished(id: UUID, successfully flag: Bool) {
        guard id == playbackID, active else { return }; playbackID = nil; player = nil; playerDelegate = nil
        guard flag else { fail("音声の再生が中断されました。"); return }
        heard += playerText; fill()
    }
    private func listen() throws {
        guard active, !recording else { return }; stopMic()
        let session = AVAudioSession.sharedInstance(); try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP]); try session.setActive(true)
        guard let recognizer, recognizer.isAvailable else { throw MobileError.message("日本語の音声認識を利用できません。") }
        recording = true; ending = false; transcript = ""; detector = SpeechTurnDetector(silence: settings["tempo"] as? String == "natural" ? 0.8 : 0.5)
        let mic = micRound, round = epoch, req = SFSpeechAudioBufferRecognitionRequest(); req.requiresOnDeviceRecognition = true; req.shouldReportPartialResults = true; request = req
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw MobileError.message("車のマイクを利用できません。") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer); guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var energy = 0.0; for i in 0..<Int(buffer.frameLength) { let v = Double(samples[i]); energy += v * v }
            let db = 20 * log10(max(0.00001, sqrt(energy / Double(buffer.frameLength)))), now = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { guard let self, self.active, self.recording, !self.ending, mic == self.micRound else { return }; if self.detector.feed(levelDB: db, now: now, hasTranscript: !self.transcript.isEmpty) { self.endInput() } }
        }; tapped = true
        speech = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async { guard let self, self.active, self.recording, mic == self.micRound else { return }
                if let result { self.transcript = result.bestTranscription.formattedString; if result.isFinal { self.submit() } }
                if error != nil, self.recording { if self.ending, !self.transcript.isEmpty { self.submit() } else { self.fail("音声認識が中断されました。会話を再開してください。") } }
            }
        }
        engine.prepare(); try engine.start(); onState("listening")
        timer?.cancel(); timer = Task { try? await Task.sleep(nanoseconds: 45_000_000_000); guard !Task.isCancelled, active, recording, round == epoch, mic == micRound else { return }; if transcript.isEmpty { stopMic(); try? listen() } else { submit() } }
    }
    private func endInput() {
        guard recording, !ending else { return }; ending = true; engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }; request?.endAudio()
        timer?.cancel(); let mic = micRound; timer = Task { try? await Task.sleep(nanoseconds: 250_000_000); guard !Task.isCancelled, active, recording, mic == micRound else { return }; submit() }
    }
    private func submit() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines); stopMic(); guard active else { return }
        if text.isEmpty { do { try listen() } catch { fail(error.localizedDescription) }; return }
        if ["会話終了", "会話を終える", "通話終了", "終了して", "もう終わり"].contains(text.replacingOccurrences(of: "。", with: "")) { stop(); return }
        onState("thinking"); let round = epoch
        let searchMode = settings["webSearch"] as? String ?? "auto"
        waitingVoice.begin(token: round, searching: searchMode != "off" && (searchMode == "on" || ConversationOptions.needsFresh(text)), settings: settings, enabled: settings["feedback"] as? Bool != false)
        let personas = ["gentle": "優しい相談相手として共感を添える。", "partner": "明るく親しみやすい相棒として話す。", "secretary": "冷静な秘書として簡潔に話す。", "explain": "落ち着いた解説役として一度に一つの要点を話す。"]
        let persona = personas[settings["persona"] as? String ?? "gentle"] ?? personas["gentle"]!
        Task { do { try await runtime.gpt.send(text, instructions: persona + "親しみやすく自然な日本語の音声会話。原則1〜3文で要点から答える。必要なら一つだけ質問する。Markdownや箇条書きを使わない。機械的な相槌を毎回入れない。調べものは確認した内容を短く説明する。", options: settings) } catch { if active, round == epoch { fail(error.localizedDescription) } } }
    }
    private func stopMic() { recording = false; ending = false; micRound += 1; timer?.cancel(); engine.stop(); if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }; request?.endAudio(); speech?.cancel(); request = nil; speech = nil }
    private func fail(_ message: String) { stop(); onError(message) }
}
