import UIKit
import GoogleMobileAds
import UserMessagingPlatform

@MainActor
final class AdBannerController: NSObject, BannerViewDelegate {
    private weak var host: UIViewController?
    private let container: UIView
    private let height: NSLayoutConstraint
    private let defaults: UserDefaults
    private var banner: BannerView?
    private var sdkStarted = false
    private var sdkReady = false
    private var consentChecked = false
    private var consentReady = false
    private var revision = 0
    private var overlay = false
    private var overlayBanner: BannerView?
    private var loadFailed = false
    private(set) var presentingConsent = false
    var changed: (() -> Void)?
    var pauseConversation: (() -> Void)?
    var nativeConversationBusy: (() -> Bool)?
    var entitlement = AdEntitlement.checking
    var foreground = true
    var settingsVisible = false
    var conversationActive = false
    var carPlay = false
    var purchasing = false
    private let preview: Bool
    private let enabled: Bool
    private let bannerID: String
    private let applicationID: String
    private var consentVersion: String { CommercePolicy.adConsentVersion + (preview ? ":test" : ":store") }
    private var audience: AdAudience? { AdAudience(rawValue: defaults.string(forKey: "adAudience") ?? "") }
    private var optedIn: Bool {
        defaults.string(forKey: "adConsentVersion") == consentVersion
            && audience != nil
    }

    init(host: UIViewController, container: UIView, height: NSLayoutConstraint,
         preview: Bool, enabled: Bool, defaults: UserDefaults = .standard) {
        self.host = host; self.container = container; self.height = height
        self.preview = preview; self.enabled = enabled; self.defaults = defaults
        applicationID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ?? ""
        bannerID = preview ? CommercePolicy.testBannerID : Bundle.main.object(forInfoDictionaryKey: "LTAdMobBannerID") as? String ?? ""
        super.init()
    }

    func snapshot() -> [String: Any] {
        ["optedIn": optedIn, "privacyBusy": presentingConsent, "adsAvailable": enabled,
         "privacyOptionsRequired": optedIn && consentChecked && ConsentInformation.shared.privacyOptionsRequirementStatus == .required,
         "adReady": consentReady, "adFailed": loadFailed, "adVisible": banner != nil && !container.isHidden]
    }
    private var eligible: Bool {
        enabled && CommercePolicy.allowsAd(entitlement: entitlement, optedIn: optedIn, consentReady: consentReady,
            foreground: foreground, settingsVisible: settingsVisible, conversationActive: conversationActive || nativeConversationBusy?() == true,
            carPlay: carPlay, presenting: presentingConsent || overlay || host?.presentedViewController != nil,
            purchasing: purchasing)
    }
    private func acceptsCompletion(_ expected: Int, requiresFree: Bool = true) -> Bool {
        CommercePolicy.acceptsConsentCompletion(expected: expected, current: revision,
            foreground: foreground, entitlement: entitlement,
            conversationActive: conversationActive || nativeConversationBusy?() == true,
            carPlay: carPlay, purchasing: purchasing, requiresFree: requiresFree)
    }
    private func configureRequests() {
        let configuration = MobileAds.shared.requestConfiguration
        configuration.publisherPrivacyPersonalizationState = .disabled
        configuration.setPublisherFirstPartyIDEnabled(false)
        configuration.maxAdContentRating = .general
        // Reapply on every load: the audience can change after SDK initialization.
        configuration.ageRestrictedTreatment = audience?.underAgeOfConsent == true ? .teen : .unspecified
    }
    func reconcile() {
        guard eligible else { destroyBanner(); return }
        guard CommercePolicy.validApplicationID(applicationID, production: !preview),
              CommercePolicy.validBannerID(bannerID, production: !preview) else {
            loadFailed = true; destroyBanner(); return
        }
        guard consentChecked else { return }
        configureRequests()
        if !sdkStarted {
            MobileAds.shared.isApplicationMuted = true
            MobileAds.shared.disableSDKCrashReporting()
            MobileAds.shared.disableMediationInitialization()
            sdkStarted = true
            MobileAds.shared.start { [weak self] _ in
                Task { @MainActor in
                    self?.sdkReady = true
                    self?.reconcile(); self?.changed?()
                }
            }
            return
        }
        guard sdkReady, banner == nil, !loadFailed, let host else { return }
        let view = BannerView(adSize: AdSizeBanner)
        view.adUnitID = bannerID; view.rootViewController = host; view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel(); label.text = preview ? "テスト広告" : "広告"
        label.font = .preferredFont(forTextStyle: .caption2); label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label); container.addSubview(view)
        NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor), view.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2)])
        banner = view; container.isHidden = false; height.constant = 76
        let request = Request(), extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        // Never attach questions, responses, account IDs, content URLs or custom targeting.
        view.load(request)
    }
    private func destroyBanner() {
        if banner !== overlayBanner { banner?.delegate = nil }
        banner?.removeFromSuperview(); banner = nil
        for view in container.subviews { view.removeFromSuperview() }
        container.isHidden = true; height.constant = 0
    }
    func disable() {
        revision += 1; consentReady = false; consentChecked = false; loadFailed = false
        defaults.removeObject(forKey: "adConsentVersion"); defaults.removeObject(forKey: "adAudience")
        destroyBanner(); changed?()
        // UMP.reset() is a testing API. Production choices are changed with the privacy form.
    }
    func suspend() { revision += 1; destroyBanner() }
    private func waitForDismissal(_ host: UIViewController) async throws {
        for _ in 0..<30 {
            if host.presentedViewController == nil { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw CommerceError.message("確認画面を閉じてから、もう一度お試しください。")
    }
    func resumeConsentIfNeeded() {
        guard enabled, optedIn, !consentChecked, !presentingConsent, entitlement == .free,
              !loadFailed, foreground, settingsVisible, !conversationActive,
              nativeConversationBusy?() != true, !carPlay, !purchasing,
              host?.presentedViewController == nil else { reconcile(); return }
        Task { [weak self] in try? await self?.refreshConsent() }
    }
    func enable() async throws -> [String: Any] {
        guard enabled else { throw CommerceError.message("広告の公開設定を準備中です。会話機能はそのまま使えます。") }
        guard entitlement == .free else { throw CommerceError.message(entitlement == .removed ? "購入済みのため、広告のデータ利用を開始しません。" : "購入状態を確認しています。少しお待ちください。") }
        guard let host, foreground, !conversationActive, !carPlay, !purchasing,
              nativeConversationBusy?() != true, !presentingConsent,
              host.presentedViewController == nil else { throw CommerceError.message("会話を終了してから広告設定を開いてください。") }
        presentingConsent = true; destroyBanner(); changed?()
        let expected = revision
        defer { presentingConsent = false; reconcile(); changed?() }
        let audience: String? = await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: preview ? "広告表示のテスト" : "無料版の広告について", message: "広告は設定画面だけに表示します。会話内容は広告会社へ渡しません。\n\nGoogleは広告配信のため、IPアドレス（おおまかな地域）、端末・広告の識別情報、広告の操作、動作情報などを処理する場合があります。広告の個人向け最適化は使いません。\n\n13〜17歳の方は保護者の同意が必要です。広告の利用を断っても、通常の会話機能は使えます。詳細は「データの取り扱い」にあります。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "広告を使わない", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "18歳以上・同意する", style: .default) { _ in continuation.resume(returning: "adult") })
            alert.addAction(UIAlertAction(title: "13〜17歳・保護者同意あり", style: .default) { _ in continuation.resume(returning: "teen") })
            host.present(alert, animated: true)
        }
        guard acceptsCompletion(expected) else {
            return ["message": "広告設定は中断されました。必要なら設定画面からやり直してください。"]
        }
        guard let audience else {
            disable(); return ["message": "広告のデータ利用を開始しませんでした。"]
        }
        consentReady = false; consentChecked = false; loadFailed = false
        defaults.set(audience, forKey: "adAudience"); defaults.set(consentVersion, forKey: "adConsentVersion")
        // UIKit dismisses an alert after invoking its action handler.
        try await waitForDismissal(host)
        guard acceptsCompletion(expected) else { return ["message": "広告設定は中断されました。"] }
        try await updateConsent(expected: expected)
        return ["message": consentReady ? preview ? "テスト広告を有効にしました。料金や広告収益は発生しません。" : "広告設定を反映しました。" : "広告は表示しません。通常の会話機能は使えます。"]
    }
    private func refreshConsent() async throws {
        guard let host, optedIn, foreground, entitlement == .free, !presentingConsent,
              !conversationActive, nativeConversationBusy?() != true, !carPlay, !purchasing,
              host.presentedViewController == nil else { return }
        presentingConsent = true; destroyBanner(); changed?()
        let expected = revision
        defer { presentingConsent = false; reconcile(); changed?() }
        try await updateConsent(expected: expected)
    }
    private func updateConsent(expected: Int) async throws {
        guard enabled, let host, optedIn, let requestedAudience = audience, acceptsCompletion(expected) else { return }
        guard CommercePolicy.validApplicationID(applicationID, production: !preview),
              CommercePolicy.validBannerID(bannerID, production: !preview) else {
            consentReady = false; consentChecked = false; loadFailed = true
            throw CommerceError.message("広告の公開設定が未完了です。通常の会話機能は使えます。")
        }
        consentReady = false; consentChecked = false
        do {
            let parameters = RequestParameters()
            parameters.isTaggedForUnderAgeOfConsent = requestedAudience.underAgeOfConsent
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            guard acceptsCompletion(expected), optedIn, audience == requestedAudience else { return }
            try await ConsentForm.loadAndPresentIfRequired(from: host)
            guard acceptsCompletion(expected), optedIn, audience == requestedAudience else { return }
            consentChecked = true; consentReady = ConsentInformation.shared.canRequestAds; loadFailed = false
        } catch {
            guard expected == revision else { return }
            consentReady = false; consentChecked = false; loadFailed = true
            throw CommerceError.message("広告設定を確認できませんでした。広告は表示せず、通常の会話機能は使えます。")
        }
    }
    func retry() async throws -> [String: Any] {
        guard enabled, optedIn, entitlement == .free, foreground, settingsVisible,
              !conversationActive, nativeConversationBusy?() != true, !carPlay, !purchasing,
              !presentingConsent, host?.presentedViewController == nil else {
            throw CommerceError.message("会話を終了し、広告の利用設定を確認してください。")
        }
        // Retry only on an explicit tap; do not loop on consent/network errors.
        loadFailed = false
        if !consentChecked { try await refreshConsent() } else { reconcile(); changed?() }
        return ["message": "広告の読み込みを再確認しました。会話機能はそのまま使えます。"]
    }
    func privacyOptions() async throws -> [String: Any] {
        guard let host, foreground, !conversationActive, !carPlay, !purchasing,
              nativeConversationBusy?() != true, !presentingConsent,
              host.presentedViewController == nil else { throw CommerceError.message("会話を終了してから広告設定を開いてください。") }
        presentingConsent = true; destroyBanner(); changed?()
        let expected = revision
        defer { presentingConsent = false; reconcile(); changed?() }
        let canManage = enabled && optedIn && consentChecked && ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        let choice = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let alert = UIAlertController(title: "広告のプライバシー", message: "広告のデータ利用を止めると、広告の表示と新しい読み込みを停止します。Googleへすでに送られた情報の削除は、Googleのプライバシー案内に従ってください。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "戻る", style: .cancel) { _ in continuation.resume(returning: "cancel") })
            alert.addAction(UIAlertAction(title: "広告のデータ利用を止める", style: .destructive) { _ in continuation.resume(returning: "disable") })
            if canManage { alert.addAction(UIAlertAction(title: "Googleの選択を変更", style: .default) { _ in continuation.resume(returning: "provider") }) }
            host.present(alert, animated: true)
        }
        guard acceptsCompletion(expected, requiresFree: false) else { return ["message": "広告設定は中断されました。"] }
        if choice == "disable" { disable(); return ["message": "広告のデータ利用を停止しました。"] }
        if choice == "provider" {
            do {
                try await waitForDismissal(host)
                guard acceptsCompletion(expected), optedIn else { return ["message": "広告設定は中断されました。"] }
                try await ConsentForm.presentPrivacyOptionsForm(from: host)
                guard acceptsCompletion(expected), optedIn else { return ["message": "広告設定は中断されました。"] }
                consentReady = ConsentInformation.shared.canRequestAds; loadFailed = false
            } catch {
                guard expected == revision else { return ["message": "広告設定は中断されました。"] }
                consentReady = false; consentChecked = false; loadFailed = true
                throw CommerceError.message("広告の選択を確認できませんでした。広告は表示しません。")
            }
        }
        reconcile(); changed?(); return ["message": "広告設定を確認しました。"]
    }
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        guard bannerView === banner else { return }; if !eligible { destroyBanner() }; changed?()
    }
    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        guard bannerView === banner else { return }; loadFailed = true; destroyBanner(); changed?()
    }
    func bannerViewWillPresentScreen(_ bannerView: BannerView) {
        guard bannerView === banner else { return }
        overlayBanner = bannerView; overlay = true; pauseConversation?(); changed?()
    }
    func bannerViewDidDismissScreen(_ bannerView: BannerView) {
        guard bannerView === overlayBanner else { return }
        overlayBanner?.delegate = nil; overlayBanner = nil; overlay = false
        reconcile(); changed?()
    }
}
