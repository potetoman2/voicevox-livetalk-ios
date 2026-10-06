import UIKit

// One credential refresh task and one synthesis queue serve both phone and car.
@MainActor
final class ConversationRuntime {
    static let shared = ConversationRuntime()
    let core = VoiceCore()
    weak var phone: LiveTalkController?
    var car: CarConversation?
    private(set) var carActive = false
    var lastCarAnswer = ""
    var lastCarSources = [[String: String]]()
    lazy var gpt = ChatGPTConnection { [weak self] event in
        guard let self else { return }
        if self.carActive { self.car?.receive(event) } else { self.phone?.receiveGPT(event) }
    }
    func takeCar(_ conversation: CarConversation) {
        gpt.stop(); carActive = true; car = conversation
        lastCarAnswer = ""; lastCarSources = []; phone?.suspendForCarPlay()
    }
    func releaseCar(_ conversation: CarConversation) {
        guard car === conversation else { return }
        gpt.stop(); carActive = false; car = nil; phone?.carPlayEnded()
    }
}
