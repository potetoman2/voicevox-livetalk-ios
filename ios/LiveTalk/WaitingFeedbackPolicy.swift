import Foundation

// Fixed, local waiting phrases never enter the assistant's reply or conversation memory.
struct WaitingFeedbackPolicy {
    static let search = "うん、調べてみるね。"
    static let thinking = "ちょっと待ってね。"
    static let reminder = "もう少し待ってね。"
    static let phrases = [search, thinking, reminder]
    private(set) var active = false
    private var started = 0.0, last = 0.0, count = 0
    mutating func begin(searching: Bool, now: Double) -> String? {
        active = true; started = now; last = now; count = 0
        return poll(searching: searching, now: now)
    }
    mutating func poll(searching: Bool = false, now: Double) -> String? {
        guard active else { return nil }
        if count == 0, searching || now - started >= 0.9 {
            count = 1; last = now; return searching ? Self.search : Self.thinking
        }
        if count == 1, now - started >= 14, now - last >= 12 {
            count = 2; last = now; return Self.reminder
        }
        return nil
    }
    mutating func stop() { active = false }
}

enum LocalBridgePolicy {
    static func allowed(_ candidate: URL?, index: URL?) -> Bool {
        guard let candidate, let index, candidate.isFileURL, index.isFileURL,
              candidate.host == nil || candidate.host == "" || candidate.host == "localhost",
              candidate.query == nil else { return false }
        return candidate.standardizedFileURL.resolvingSymlinksInPath().path == index.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum DataConsent {
    static let version = "openai-text-search:2026-10-06:1"
    static func accepted(_ defaults: UserDefaults = .standard) -> Bool { defaults.string(forKey: "dataConsentVersion") == version }
}
