import AVFoundation

// AVFoundation may finish on a different thread. Transfer only a value to the
// main actor; each player retains its own immutable callback through its owner.
final class AudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
    private let finished: @MainActor @Sendable (Bool) -> Void
    init(finished: @escaping @MainActor @Sendable (Bool) -> Void) {
        self.finished = finished
        super.init()
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        deliver(flag)
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        deliver(false)
    }
    private func deliver(_ success: Bool) {
        let callback = finished
        Task { @MainActor in callback(success) }
    }
}
