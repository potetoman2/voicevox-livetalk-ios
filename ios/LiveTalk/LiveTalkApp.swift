import SwiftUI

@main
struct LiveTalkApp: App {
    var body: some Scene { WindowGroup { MobileHost().ignoresSafeArea(.keyboard).onOpenURL { url in NotificationCenter.default.post(name: Notification.Name("LiveTalkIncomingURL"), object: url) } } }
}
struct MobileHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LiveTalkController { LiveTalkController() }
    func updateUIViewController(_ controller: LiveTalkController, context: Context) {}
}
