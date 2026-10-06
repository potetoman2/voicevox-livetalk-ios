import Foundation

/// End a turn on microphone silence, rather than on a pause in transcript updates.
/// Uses only levels and timing; no microphone audio is retained.
struct SpeechTurnDetector {
    private var noiseFloor = -60.0
    private var lastVoice: TimeInterval?
    private var ended = false
    let silence: TimeInterval
    init(silence: TimeInterval = 0.7) { self.silence = silence }

    mutating func feed(levelDB: Double, now: TimeInterval, hasTranscript: Bool) -> Bool {
        guard !ended, levelDB.isFinite, now.isFinite else { return false }
        if !hasTranscript { noiseFloor = max(-70, min(-42, noiseFloor * 0.98 + levelDB * 0.02)) }
        let threshold = max(-50, min(-30, noiseFloor + 12))
        if levelDB > threshold { lastVoice = now; return false }
        guard hasTranscript, let lastVoice, now - lastVoice >= silence else { return false }
        ended = true
        return true
    }
}
