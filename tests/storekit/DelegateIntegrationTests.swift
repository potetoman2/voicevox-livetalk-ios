import XCTest
import AVFoundation
import SafariServices
@testable import CommerceHost

final class DelegateIntegrationTests: XCTestCase {
    private static func player() throws -> AVAudioPlayer {
        // A real, minimal PCM WAV, without a microphone, playback or external data.
        let header: [UInt8] = [82,73,70,70,38,0,0,0,87,65,86,69,102,109,116,32,
            16,0,0,0,1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,100,97,116,97,2,0,0,0,0,0]
        return try AVAudioPlayer(data: Data(header))
    }
    @MainActor
    func testPlaybackFinishFromWorkerArrivesOnMainThread() async throws {
        let done = expectation(description: "main actor playback finish")
        let delegate = AudioPlaybackDelegate { success in
            XCTAssertTrue(Thread.isMainThread); XCTAssertTrue(success); done.fulfill()
        }
        try await Task.detached {
            XCTAssertFalse(Thread.isMainThread)
            delegate.audioPlayerDidFinishPlaying(try Self.player(), successfully: true)
        }.value
        await fulfillment(of: [done], timeout: 3)
    }
    @MainActor
    func testDecodeFailureFromWorkerArrivesOnMainThread() async throws {
        let done = expectation(description: "main actor decode failure")
        let delegate = AudioPlaybackDelegate { success in
            XCTAssertTrue(Thread.isMainThread); XCTAssertFalse(success); done.fulfill()
        }
        try await Task.detached {
            delegate.audioPlayerDecodeErrorDidOccur(try Self.player(), error: NSError(domain: "fixture", code: 1))
        }.value
        await fulfillment(of: [done], timeout: 3)
    }
    @MainActor
    func testSafariDismissalIsDeliveredAsynchronouslyOnMainThread() async {
        let done = expectation(description: "main actor Safari dismissal")
        var delivered = false
        let delegate = LoginDismissDelegate {
            XCTAssertTrue(Thread.isMainThread); delivered = true; done.fulfill()
        }
        let safari = SFSafariViewController(url: URL(string: "https://example.com")!)
        delegate.safariViewControllerDidFinish(safari)
        XCTAssertFalse(delivered, "A callback must not mutate actor state synchronously")
        await fulfillment(of: [done], timeout: 3)
        XCTAssertTrue(delivered)
    }
}
