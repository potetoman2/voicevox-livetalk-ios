import SafariServices

// Do not carry the Safari controller across actor boundaries. The callback
// captures the specific login attempt, so a delayed close cannot cancel another.
final class LoginDismissDelegate: NSObject, SFSafariViewControllerDelegate, Sendable {
    private let dismissed: @MainActor @Sendable () -> Void
    init(dismissed: @escaping @MainActor @Sendable () -> Void) {
        self.dismissed = dismissed
        super.init()
    }
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        let callback = dismissed
        Task { @MainActor in callback() }
    }
}
