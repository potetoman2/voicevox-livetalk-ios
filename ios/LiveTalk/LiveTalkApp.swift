import UIKit

@main
final class LiveTalkApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let controller = LiveTalkController(), window = UIWindow(windowScene: scene)
        window.rootViewController = controller; self.window = window; window.makeKeyAndVisible()
        for context in connectionOptions.urlContexts { controller.acceptIncomingURL(context.url) }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts { (window?.rootViewController as? LiveTalkController)?.acceptIncomingURL(context.url) }
    }
}
