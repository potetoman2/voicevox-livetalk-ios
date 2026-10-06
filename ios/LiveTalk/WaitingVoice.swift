import AVFoundation

@MainActor
final class WaitingVoice: NSObject, AVAudioPlayerDelegate {
    private let core: VoiceCore
    private let activate: () throws -> Void
    private var policy = WaitingFeedbackPolicy()
    private var timer: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var cache = [String: Data]()
    private var key = "", settings = [String: Any]()
    private var epoch = 0, token = -1, warming = 0
    var active: Bool { policy.active }
    init(core: VoiceCore, activate: @escaping () throws -> Void) { self.core = core; self.activate = activate; super.init() }
    func warm(_ value: [String: Any]) {
        let keys = ["style", "speed", "pitch", "intonation", "volume"]
        var filtered = [String: Any]()
        for field in keys { if let number = value[field] as? NSNumber { filtered[field] = number } }
        filtered["pre"] = 0.02; filtered["post"] = 0.02; filtered["comma"] = 0.05; filtered["sentence"] = 0.02
        guard let data = try? JSONSerialization.data(withJSONObject: filtered, options: .sortedKeys), let next = String(data: data, encoding: .utf8) else { return }
        settings = filtered
        guard next != key else { return }; key = next; cache.removeAll(); warming += 1
        let revision = warming
        func one(_ index: Int) {
            guard revision == self.warming, index < WaitingFeedbackPolicy.phrases.count else { return }
            let phrase = WaitingFeedbackPolicy.phrases[index]
            self.core.synthesize(text: phrase, settings: filtered) { [weak self] result in
                guard let self, revision == self.warming else { return }
                if case .success(let wav) = result { self.cache[phrase] = wav }
                if !self.policy.active { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { one(index + 1) } }
            }
        }
        one(0)
    }
    func begin(token: Int, searching: Bool, settings: [String: Any], enabled: Bool) {
        stop(); self.token = token
        guard enabled, (settings["volume"] as? NSNumber)?.doubleValue != 0 else { return }
        warm(settings); let round = epoch
        if let phrase = policy.begin(searching: searching, now: ProcessInfo.processInfo.systemUptime) { speak(phrase, round: round) }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let self, round == self.epoch, self.policy.active else { return }
                if let phrase = self.policy.poll(now: ProcessInfo.processInfo.systemUptime) { self.speak(phrase, round: round) }
            }
        }
    }
    func searching(token: Int) {
        guard token == self.token else { return }
        if let phrase = policy.poll(searching: true, now: ProcessInfo.processInfo.systemUptime) { speak(phrase, round: epoch) }
    }
    func retag(from old: Int, to next: Int) { if token == old { token = next } }
    func stop() { epoch += 1; policy.stop(); timer?.cancel(); timer = nil; player?.stop(); player = nil; token = -1 }
    private func speak(_ phrase: String, round: Int) {
        guard policy.active, round == epoch else { return }
        if let wav = cache[phrase] { play(wav, round: round); return }
        let revision = warming
        core.synthesize(text: phrase, settings: settings) { [weak self] result in
            guard let self, revision == self.warming else { return }
            if case .success(let wav) = result { self.cache[phrase] = wav; self.play(wav, round: round) }
        }
    }
    private func play(_ wav: Data, round: Int) {
        guard policy.active, round == epoch, player == nil else { return }
        do { try activate(); let voice = try AVAudioPlayer(data: wav); voice.delegate = self; voice.prepareToPlay(); player = voice; if !voice.play() { player = nil } }
        catch { player = nil } // A waiting hint must never stop the actual answer.
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { if player === self.player { self.player = nil } }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { if player === self.player { self.player = nil } }
}
