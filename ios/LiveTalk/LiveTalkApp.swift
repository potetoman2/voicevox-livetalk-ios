import SwiftUI

@main
struct LiveTalkApp: App {
    var body: some Scene { WindowGroup { MobileHost().ignoresSafeArea(.keyboard) } }
}
struct MobileHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LiveTalkController { LiveTalkController() }
    func updateUIViewController(_ controller: LiveTalkController, context: Context) {}
}
