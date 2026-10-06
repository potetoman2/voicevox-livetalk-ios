import UIKit
import WebKit
import AVFoundation
import AudioToolbox
import Speech
import UniformTypeIdentifiers

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var owner: LiveTalkController?
    init(_ owner: LiveTalkController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

final class LiveTalkController: UIViewController, WKNavigationDelegate, WKUIDelegate, AVAudioPlayerDelegate, UIDocumentPickerDelegate {
    private var app: WKWebView!
    private var chat: WKWebView!
    private var chatPanel: UIStackView!
    private let chatLabel = UILabel()
    private let core = ConversationRuntime.shared.core
    private var gpt: ChatGPTConnection { ConversationRuntime.shared.gpt }
    private var planUsageAllowed: Bool { Bundle.main.object(forInfoDictionaryKey: "LTPlanUsageEnabled") as? Bool == true }
    private var experimentalAllowed: Bool { Bundle.main.object(forInfoDictionaryKey: "LTExperimentalChatEnabled") as? Bool == true }
    private var generation = 0
    private var loaded = false
    private var incoming: String?
    private var foreground = true
    private var player: AVAudioPlayer?
    private var playId: Int?
    private var playingFile: URL?
    private var documentId: Int?
    private var chatRequests = Set<Int>()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var speechTask: SFSpeechRecognitionTask?
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionRound = 0
    private var recognitionToken = 0
    private var listening = false
    private var tapInstalled = false
    private var speechTimeout: DispatchWorkItem?
    private var turnDetector = SpeechTurnDetector()
    private var latestTranscript = ""
    private var finalizingSpeech = false
    private var turnSilence = 0.5
    private var finalWait = 0.25
    private let defaults = UserDefaults.standard
    private let termsVersion = "0.16.0:model0:2"
    private var deletingData = false
    private let adArea = UIView()
    private var adHeight: NSLayoutConstraint!
    private lazy var commerce = AdRemovalStore(enabled: Bundle.main.object(forInfoDictionaryKey: "LTCommerceEnabled") as? Bool == true)
    private lazy var advertising = AdBannerController(host: self, container: adArea, height: adHeight, preview: !commerce.enabled)
    private var indexURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("shared/index.html") }
    private lazy var waitingVoice = WaitingVoice(core: core) { [weak self] in try self?.audioSession() }
    private var waves: URL { FileManager.default.temporaryDirectory.appendingPathComponent("livetalk-waves", isDirectory: true) }

    override func viewDidLoad() {
        super.viewDidLoad(); ConversationRuntime.shared.phone = self; view.backgroundColor = .systemBackground
        try? FileManager.default.createDirectory(at: waves, withIntermediateDirectories: true)
        cleanWaves()
        let local = WKWebViewConfiguration(); local.websiteDataStore = .nonPersistent()
        local.userContentController.add(WeakHandler(self), name: "native")
        app = WKWebView(frame: .zero, configuration: local); app.navigationDelegate = self
        let remote = WKWebViewConfiguration()
        remote.userContentController.add(WeakHandler(self), name: "chatEvent")
        remote.websiteDataStore = .default()
        if experimentalAllowed, let shared = Bundle.main.resourceURL?.appendingPathComponent("shared"),
           let dom = try? String(contentsOf: shared.appendingPathComponent("dom.js"), encoding: .utf8),
           let bridge = try? String(contentsOf: shared.appendingPathComponent("chat-bridge.js"), encoding: .utf8) {
            remote.userContentController.addUserScript(WKUserScript(source: "if(location.hostname==='chatgpt.com'){" + dom + bridge + "}", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        chat = WKWebView(frame: .zero, configuration: remote); chat.navigationDelegate = self; chat.uiDelegate = self
        let toolbar = UIStackView(); toolbar.axis = .horizontal; toolbar.distribution = .fillEqually
        let back = UIButton(type: .system); back.setTitle("戻る", for: .normal); back.addTarget(self, action: #selector(closeChat), for: .touchUpInside)
        let attach = UIButton(type: .system); attach.setTitle("接続する", for: .normal); attach.addTarget(self, action: #selector(attachChat), for: .touchUpInside)
        let reload = UIButton(type: .system); reload.setTitle("再読込", for: .normal); reload.addTarget(self, action: #selector(reloadChat), for: .touchUpInside)
        toolbar.addArrangedSubview(back); toolbar.addArrangedSubview(reload); toolbar.addArrangedSubview(attach); toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        chatLabel.text = "ログイン後、入力欄が表示されたら「接続する」"; chatLabel.font = .preferredFont(forTextStyle: .caption1); chatLabel.numberOfLines = 0; chatLabel.textAlignment = .center; chatLabel.accessibilityTraits = .updatesFrequently
        chatPanel = UIStackView(arrangedSubviews: [toolbar, chatLabel, chat]); chatPanel.axis = .vertical
        adArea.translatesAutoresizingMaskIntoConstraints = false; adArea.isHidden = true
        view.addSubview(adArea); adHeight = adArea.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([adArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            adArea.trailingAnchor.constraint(equalTo: view.trailingAnchor), adArea.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor), adHeight])
        for web in [app!, chatPanel!] as [UIView] {
            web.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(web)
            NSLayoutConstraint.activate([web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor), web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), web.bottomAnchor.constraint(equalTo: web === app ? adArea.topAnchor : view.safeAreaLayoutGuide.bottomAnchor)])
        }
        chatPanel.isHidden = true
        commerce.changed = { [weak self] in guard let self else { return }; self.advertising.entitlement = self.commerce.entitlement; self.advertising.purchasing = self.commerce.busy; self.advertising.resumeConsentIfNeeded(); self.commerceChanged() }
        advertising.changed = { [weak self] in self?.commerceChanged() }
        advertising.nativeConversationBusy = { [weak self] in guard let self else { return true }; return self.listening || self.player != nil || self.waitingVoice.active }
        advertising.pauseConversation = { [weak self] in
            guard let self else { return }; self.generation += 1; self.gpt.stop(); self.stopRecognition(); self.stopPlayer(); self.event(["type": "adOverlay"])
        }
        commerce.start()
        if let shared = Bundle.main.resourceURL?.appendingPathComponent("shared") { app.loadFileURL(shared.appendingPathComponent("index.html"), allowingReadAccessTo: shared) }
        NotificationCenter.default.addObserver(self, selector: #selector(fontChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(incomingURL), name: Notification.Name("LiveTalkIncomingURL"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func js(_ value: Any) -> String { guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let text = String(data: data, encoding: .utf8) else { return "null" }; return text }
    private func reply(_ id: Int, _ result: Any? = nil, _ error: String? = nil) {
        DispatchQueue.main.async { [weak self] in guard let self, self.loaded else { return }; self.app.evaluateJavaScript("window.LiveTalkReply(\(id),\(self.js(result ?? NSNull())),\(self.js(error as Any? ?? NSNull())))", completionHandler: nil) }
    }
    private func event(_ value: [String: Any]) { if loaded { app.evaluateJavaScript("window.LiveTalkEvent(\(js(value)))", completionHandler: nil) } }
    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        if message.name == "chatEvent" {
            guard message.webView === chat, message.frameInfo.request.url?.host == "chatgpt.com", chat.url?.scheme == "https", chat.url?.host == "chatgpt.com", let e = message.body as? [String: Any] else { return }
            if e["type"] as? String == "ack", let id = e["id"] as? Int, chatRequests.remove(id) != nil { reply(id, true, e["error"] as? String) }
            else {
                let types = ["attached", "detached", "connectionError", "chatLoaded", "waiting", "start", "snapshot", "error"]
                guard let type = e["type"] as? String, types.contains(type) else { return }
                if let text = e["text"] as? String, text.utf16.count > 12000 { event(["type": "error", "message": "返答が長すぎます。文章を分けて読み上げてください。"]); return }
                event(e)
            }
            return
        }
        guard message.name == "native", message.webView === app, LocalBridgePolicy.allowed(message.frameInfo.request.url, index: indexURL),
              let raw = message.body as? String, raw.utf8.count <= 65536, let data = raw.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = m["id"] as? Int, id > 0, let command = m["command"] as? String else { return }
        loaded = true
        handle(id, command, (m["args"] as? [String: Any]) ?? [:])
    }
    func receiveGPT(_ value: [String: Any]) { event(value) }
    private func commerceSnapshot() -> [String: Any] { commerce.snapshot().merging(advertising.snapshot(), uniquingKeysWith: { _, new in new }) }
    private func commerceChanged() { advertising.reconcile(); event(["type": "commerce", "value": commerceSnapshot()]) }
    private func suspendAdsForConversation() { advertising.conversationActive = true; advertising.suspend() }
    func suspendForCarPlay() {
        advertising.carPlay = true; advertising.suspend()
        generation += 1; waitingVoice.stop(); stopRecognition(); stopPlayer(); event(["type": "carplay", "active": true])
    }
    func carPlayEnded() {
        advertising.carPlay = false; advertising.conversationActive = false; advertising.resumeConsentIfNeeded()
        event(["type": "carplay", "active": !foreground]);
        if foreground { restoreCarAnswer() }
    }
    private func restoreCarAnswer() {
        let runtime = ConversationRuntime.shared
        if !runtime.lastCarAnswer.isEmpty { event(["type": "carplayResponse", "text": runtime.lastCarAnswer, "sources": runtime.lastCarSources]) }
    }
    private func handle(_ id: Int, _ command: String, _ args: [String: Any]) {
        if deletingData && !["gptStop", "stop", "asrStop"].contains(command) { reply(id, nil, "データを削除しています。少しお待ちください。"); return }
        if ConversationRuntime.shared.carActive && (command.hasPrefix("gpt") || ["init", "asrStart", "synthesize", "play", "chatSend"].contains(command)) { reply(id, nil, "cancelled"); return }
        if command.hasPrefix("gpt") {
            guard planUsageAllowed else { reply(id, nil, "この配布版ではChatGPTの利用枠による連携を利用できません。"); return }
            if ["gptSend", "gptSignIn", "gptAccount"].contains(command), commerce.busy || advertising.presentingConsent || presentedViewController != nil {
                reply(id, nil, "購入・設定画面を閉じてから会話を始めてください。"); return
            }
            if ["gptSend", "gptSignIn", "gptAccount"].contains(command) { suspendAdsForConversation() }
            switch command {
            case "gptStop": gpt.stop(heard: args["heard"] as? String, responseID: args["responseID"] as? String); reply(id, true)
            case "gptManageUsage": UIApplication.shared.open(URL(string: "https://chatgpt.com/settings/usage")!); reply(id, true)
            default:
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        switch command {
                        case "gptStatus":
                            if !DataConsent.accepted() { self.reply(id, ["authenticated": false, "consentRequired": true, "accounts": [], "models": []]); return }
                            self.reply(id, try await self.gpt.status(restore: (args["restore"] as? Bool) ?? false))
                        case "gptSignIn":
                            guard await self.confirmDataConsent(), self.foreground, !self.deletingData else { throw ChatGPTError.message("cancelled") }
                            self.reply(id, try await self.gpt.signIn(from: self, newAccount: (args["newAccount"] as? Bool) ?? false))
                        case "gptSignOut": self.reply(id, try await self.gpt.signOut())
                        case "gptAccount":
                            guard DataConsent.accepted() else { throw ChatGPTError.message("ChatGPTへの送信内容を確認し、接続し直してください。") }
                            self.reply(id, try await self.gpt.selectAccount((args["account"] as? String) ?? ""))
                        case "gptModel": try self.gpt.selectModel((args["model"] as? String) ?? ""); self.reply(id, true)
                        case "gptSend":
                            guard DataConsent.accepted() else { throw ChatGPTError.message("ChatGPTへの送信内容を確認し、接続し直してください。") }
                            guard self.foreground else { throw ChatGPTError.message("画面を開いてから話しかけてください。") }
                            let instructions = String(((args["instructions"] as? String) ?? "日本語で自然に会話してください。").prefix(3000))
                            try await self.gpt.send((args["text"] as? String) ?? "", instructions: instructions, options: args); self.reply(id, true)
                        default: self.reply(id, nil, "未対応の接続操作です。")
                        }
                    } catch { self.reply(id, nil, (error as? ChatGPTError)?.localizedDescription ?? "ChatGPTへの接続を確認できません。通信を確認してお試しください。") }
                }
            }
            return
        }
        switch command {
        case "commerceStatus": reply(id, commerceSnapshot())
        case "commerceContext":
            advertising.settingsVisible = args["settingsVisible"] as? Bool == true && chatPanel.isHidden
            advertising.conversationActive = args["conversationActive"] as? Bool == true
            advertising.foreground = foreground; advertising.carPlay = ConversationRuntime.shared.carActive
            advertising.resumeConsentIfNeeded(); reply(id, true)
        case "purchaseAdRemoval", "restorePurchases", "commerceRefresh", "adEnable", "adPrivacy":
            guard foreground, !ConversationRuntime.shared.carActive, !listening, player == nil,
                  !advertising.conversationActive, !advertising.presentingConsent, presentedViewController == nil else {
                reply(id, nil, "会話を終了してから購入・広告設定を開いてください。"); return
            }
            advertising.suspend()
            Task { [weak self] in
                guard let self else { return }
                do {
                    let result: [String: Any]
                    switch command {
                    case "purchaseAdRemoval": result = try await self.commerce.purchase()
                    case "restorePurchases": result = try await self.commerce.restore()
                    case "commerceRefresh": result = try await self.commerce.refreshPurchaseInfo()
                    case "adEnable": result = try await self.advertising.enable()
                    default: result = try await self.advertising.privacyOptions()
                    }
                    self.commerceChanged(); self.reply(id, self.commerceSnapshot().merging(result, uniquingKeysWith: { _, new in new }))
                } catch { self.commerceChanged(); self.reply(id, nil, (error as? CommerceError)?.localizedDescription ?? "購入・広告設定を完了できませんでした。時間をおいてお試しください。") }
            }
        case "loadSettings":
            let data = defaults.data(forKey: "settings")
            reply(id, data.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:])
        case "saveSettings": do {
            guard let settings = args["settings"] as? [String: Any] else { throw MobileError.message("設定の形式が正しくありません") }
            let data = try JSONSerialization.data(withJSONObject: settings); guard data.count <= 65536 else { throw MobileError.message("設定が大きすぎます") }
            defaults.set(data, forKey: "settings"); reply(id, true)
        } catch { reply(id, nil, error.localizedDescription) }
        case "init": prepare(id, interactive: (args["interactive"] as? Bool) ?? false)
        case "synthesize": suspendAdsForConversation(); synthesize(id, args)
        case "play": suspendAdsForConversation(); play(id, args)
        case "stop":
            let previous = generation; generation = (args["generation"] as? Int) ?? (generation + 1)
            let keep = args["keepFeedback"] as? Bool == true && foreground
            if keep { waitingVoice.retag(from: previous, to: generation) }
            stopPlayer(stopWaiting: !keep); cleanWaves(); reply(id, true)
        case "discard": if let name = args["file"] as? String, let url = audioFile(name) { try? FileManager.default.removeItem(at: url) }; reply(id, true)
        case "asrStart":
            guard !commerce.busy, !advertising.presentingConsent, presentedViewController == nil else { reply(id, nil, "購入・設定画面を閉じてから会話を始めてください。"); return }
            suspendAdsForConversation(); turnSilence = (args["tempo"] as? String) == "natural" ? 0.8 : 0.5; finalWait = (args["tempo"] as? String) == "natural" ? 0.4 : 0.25; startRecognition(id, headset: (args["headset"] as? Bool) ?? false, token: (args["token"] as? Int) ?? 0)
        case "asrStop": stopRecognition(); reply(id, true)
        case "showLicenses": showVoiceTerms(requiresAcceptance: false) { _ in self.reply(id, true) }
        case "showPrivacy": showDocument("privacy.txt", title: "データの取り扱い", id: id)
        case "showTerms": showDocument("terms.txt", title: "アプリの利用条件", id: id)
        case "showAdLicenses": showDocument("google-notices.txt", title: "広告サービスの利用条件", id: id)
        case "deleteLocalData": confirmDeleteData(id)
        case "feedbackWarm": if args["enabled"] as? Bool == true { waitingVoice.warm(args["settings"] as? [String: Any] ?? [:]) }; reply(id, true)
        case "feedbackBegin":
            guard foreground, args["generation"] as? Int == generation else { reply(id, true); return }
            let text = args["text"] as? String ?? "", mode = args["webSearch"] as? String ?? "auto"
            waitingVoice.begin(token: generation, searching: mode != "off" && (mode == "on" || ConversationOptions.needsFresh(text)), settings: args["settings"] as? [String: Any] ?? [:], enabled: args["enabled"] as? Bool == true)
            reply(id, true)
        case "feedbackSearch": if args["generation"] as? Int == generation { waitingVoice.searching(token: generation) }; reply(id, true)
        case "feedbackStop": waitingVoice.stop(); reply(id, true)
        case "confirmReset":
            let alert = UIAlertController(title: "設定を初期設定に戻しますか？", message: "声や通話の設定が初期値に戻ります。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in self.reply(id, false) })
            alert.addAction(UIAlertAction(title: "戻す", style: .destructive) { _ in self.reply(id, true) }); present(alert, animated: true)
        case "openSettings": if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }; reply(id, true)
        case "contactSupport":
            // Opening a draft does not send it. No conversation or diagnostic data is attached.
            if let url = URL(string: "mailto:doude424@gmail.com?subject=LiveTalk%202.4%20support") { UIApplication.shared.open(url) }; reply(id, true)
        case "chatOpen": guard experimentalAllowed else { reply(id, nil, "この配布版は貼り付け読み上げ専用です。"); return }; advertising.settingsVisible = false; advertising.suspend(); chatPanel.isHidden = false; if chat.url == nil { chat.load(URLRequest(url: URL(string: "https://chatgpt.com/")!)) }; reply(id, true)
        case "chatSend": chatCommand(id, method: "send", text: (args["text"] as? String) ?? "")
        case "chatDetach": if chat.url?.host == "chatgpt.com" { chatCommand(id, method: "detach", text: "") } else { reply(id, true) }
        case "chatStop": if chat.url?.host == "chatgpt.com" { chatCommand(id, method: "stop", text: "") } else { reply(id, true) }
        case "copy": UIPasteboard.general.string = args["text"] as? String; reply(id, true)
        case "paste": reply(id, UIPasteboard.general.string ?? "")
        case "exportSettings": export(id, settings: args["settings"] ?? [:])
        case "importSettings": if documentId != nil { reply(id, nil, "ファイル選択中です"); return }; documentId = id; let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true); picker.delegate = self; present(picker, animated: true)
        case "openSource":
            guard let raw = args["url"] as? String, raw.count <= 2048, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { reply(id, nil, "リンクを開けません"); return }
            UIApplication.shared.open(url); reply(id, true)
        case "cue": AudioServicesPlaySystemSound(1104); reply(id, true)
        default: reply(id, nil, "未対応の操作です")
        }
    }
    private func prepare(_ id: Int, interactive: Bool) {
        if defaults.string(forKey: "voiceTermsVersion") != termsVersion {
            guard interactive else { reply(id, nil, "「音声を準備する」から利用条件を確認してください"); return }
            showVoiceTerms { [weak self] agreed in
                guard let self else { return }
                if agreed { self.defaults.set(self.termsVersion, forKey: "voiceTermsVersion"); self.prepare(id, interactive: false) }
                else { self.reply(id, nil, "音声の利用条件への同意が必要です。準備はいつでも再開できます。") }
            }; return
        }
        core.prepare { [weak self] result in guard let self else { return }; switch result {
        case .success(let styles): self.reply(id, ["styles": styles, "experimentalAvailable": self.experimentalAllowed, "planUsageAvailable": self.planUsageAllowed, "platform": "iOS", "asrAvailable": self.recognizer?.supportsOnDeviceRecognition ?? false])
        case .failure(let error): self.reply(id, nil, "VOICEVOXを準備できませんでした: " + error.localizedDescription)
        } }
    }
    private func confirmDataConsent() async -> Bool {
        if DataConsent.accepted() { return true }
        guard foreground, presentedViewController == nil else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: "ChatGPTへ送る内容を確認", message: "質問の文字と直近の会話をOpenAIへ送信します。検索時には関連する検索語も処理されます。ログインではアカウント識別情報とこの端末の登録IDを使います。\n\nマイクの音声と音声合成はiPhone内で処理します。会話本文はアプリに保存しません。OpenAI側の保存・利用条件も適用されます。\n\n設定の「データの取り扱い」で詳細を確認でき、「同意を撤回・端末のデータを削除」で取り消せます。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "今は接続しない", style: .cancel) { _ in continuation.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "同意して接続する", style: .default) { [weak self] _ in
                let accepted = self?.foreground == true
                if accepted { self?.defaults.set(DataConsent.version, forKey: "dataConsentVersion") }
                continuation.resume(returning: accepted)
            })
            present(alert, animated: true)
        }
    }
    private func showDocument(_ name: String, title: String, id: Int) {
        guard presentedViewController == nil, let path = Bundle.main.resourceURL?.appendingPathComponent("shared/" + name), let text = try? String(contentsOf: path, encoding: .utf8) else { reply(id, nil, "説明を開けませんでした。"); return }
        let screen = VoiceTermsController(text: text, requiresAcceptance: false, heading: title, introduction: "LiveTalk 2.4 · 公開準備版") { _ in self.reply(id, true) }
        present(screen, animated: true)
    }
    private func confirmDeleteData(_ id: Int) {
        guard foreground, presentedViewController == nil else { reply(id, nil, "画面を開いてからお試しください。"); return }
        let alert = UIAlertController(title: "同意を撤回し、端末のデータを削除しますか？", message: "保存したすべてのChatGPT接続、声の設定、利用条件と広告の同意、一時音声を削除します。広告の読み込みも停止します。OpenAI・Google側の記録や、他のアプリに書き出した設定ファイルは削除されません。広告除去の購入はAppleに残り、消えません。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel) { _ in self.reply(id, ["cancelled": true]) })
        alert.addAction(UIAlertAction(title: "撤回して削除", style: .destructive) { [weak self] _ in
            guard let self else { return }; self.deletingData = true
            self.advertising.disable()
            self.defaults.removeObject(forKey: "dataConsentVersion"); ConversationRuntime.shared.car?.stop()
            self.generation += 1; self.waitingVoice.stop(); self.stopRecognition(); self.stopPlayer(); self.cleanWaves()
            Task {
                do {
                    let result = try await self.gpt.deleteLocalData()
                    for key in ["settings", "voiceTermsVersion"] { self.defaults.removeObject(forKey: key) }
                    let exported = FileManager.default.temporaryDirectory.appendingPathComponent("livetalk-settings.json"); try? FileManager.default.removeItem(at: exported)
                    ConversationRuntime.shared.lastCarAnswer = ""; ConversationRuntime.shared.lastCarSources = []
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { continuation.resume() } }
                    self.deletingData = false; self.reply(id, result)
                } catch { self.deletingData = false; self.reply(id, nil, "同意は撤回しましたが、削除を完了できません。ロックを解除して再実行してください。") }
            }
        })
        present(alert, animated: true)
    }
    private func showVoiceTerms(requiresAcceptance: Bool = true, completion: @escaping (Bool) -> Void) {
        guard presentedViewController == nil, let url = Bundle.main.resourceURL?.appendingPathComponent("voice/NOTICE.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { completion(false); return }
        present(VoiceTermsController(text: text, requiresAcceptance: requiresAcceptance, completion: completion), animated: true)
    }
    private func synthesize(_ id: Int, _ args: [String: Any]) {
        guard let gen = args["generation"] as? Int, gen == generation, foreground else { reply(id, nil, "cancelled"); return }
        core.synthesize(text: (args["text"] as? String) ?? "", settings: (args["settings"] as? [String: Any]) ?? [:]) { [weak self] result in
            guard let self else { return }; guard gen == self.generation, self.foreground else { self.reply(id, nil, "cancelled"); return }
            switch result {
            case .success(let data): do { let name = UUID().uuidString.lowercased() + ".wav"; try data.write(to: self.waves.appendingPathComponent(name), options: [.atomic, .completeFileProtection]); self.reply(id, name) } catch { self.reply(id, nil, error.localizedDescription) }
            case .failure(let error): self.reply(id, nil, error.localizedDescription)
            }
        }
    }
    private func audioFile(_ name: String) -> URL? { guard name.range(of: "^[a-f0-9-]{36}\\.wav$", options: .regularExpression) != nil else { return nil }; return waves.appendingPathComponent(name) }
    private func play(_ id: Int, _ args: [String: Any]) {
        guard foreground, args["generation"] as? Int == generation, let name = args["file"] as? String, let url = audioFile(name) else { reply(id, nil, "cancelled"); return }
        do {
            waitingVoice.stop(); stopPlayer(); try audioSession()
            player = try AVAudioPlayer(contentsOf: url); playId = id; playingFile = url; player?.delegate = self; player?.prepareToPlay()
            if player?.play() != true { throw MobileError.message("音声を再生できません") }; event(["type": "audioStarted", "generation": generation])
        } catch { playId = nil; stopPlayer(); reply(id, nil, error.localizedDescription) }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }; let id = playId; self.player = nil; playId = nil
        if let file = playingFile { try? FileManager.default.removeItem(at: file) }; playingFile = nil
        if let id { reply(id, true, flag ? nil : "音声の再生が中断されました") }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { guard player === self.player else { return }; let id = playId; playId = nil; stopPlayer(); if let id { reply(id, nil, error?.localizedDescription ?? "音声を再生できません") } }
    private func stopPlayer(stopWaiting: Bool = true) { if stopWaiting { waitingVoice.stop() }; player?.stop(); player = nil; if let id = playId { reply(id, nil, "cancelled") }; playId = nil; if let file = playingFile { try? FileManager.default.removeItem(at: file) }; playingFile = nil }
    private func cleanWaves() { if let files = try? FileManager.default.contentsOfDirectory(at: waves, includingPropertiesForKeys: nil) { for file in files { try? FileManager.default.removeItem(at: file) } } }
    private func audioSession() throws { let session = AVAudioSession.sharedInstance(); try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]); try session.setActive(true) }
    private func hasHeadset() -> Bool { AVAudioSession.sharedInstance().currentRoute.outputs.contains { [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) } }
    private func startRecognition(_ id: Int, headset: Bool, token: Int) {
        guard foreground else { reply(id, nil, "画面を開いてから話しかけてください"); return }
        guard recognizer?.supportsOnDeviceRecognition == true else { reply(id, nil, "端末内の日本語音声認識に対応していません。文字入力をご利用ください"); return }
        if headset && !hasHeadset() { reply(id, nil, "イヤホンを接続するか、イヤホン設定を解除してください"); return }
        stopRecognition(); recognitionToken = token
        let permissionRound = recognitionRound
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { guard let self else { return }; guard permissionRound == self.recognitionRound else { self.reply(id, nil, "cancelled"); return }; guard status == .authorized else { self.reply(id, nil, "音声認識が許可されていません"); return }
                AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in DispatchQueue.main.async { guard let self else { return }; guard permissionRound == self.recognitionRound else { self.reply(id, nil, "cancelled"); return }; if allowed { self.beginRecognition(id) } else { self.reply(id, nil, "マイクが許可されていません") } } }
            }
        }
    }
    private func beginRecognition(_ id: Int) {
        guard foreground else { reply(id, nil, "cancelled"); return }
        do {
            stopRecognition(); try audioSession()
            guard let recognizer, recognizer.isAvailable else { throw MobileError.message("音声認識を利用できません。日本語の端末内音声認識を確認してください") }
            let round = recognitionRound; let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            speechRequest = request; listening = true; latestTranscript = ""; finalizingSpeech = false; turnDetector = SpeechTurnDetector(silence: turnSilence)
            let input = audioEngine.inputNode; let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw MobileError.message("マイクを利用できません") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var energy = 0.0
                for i in 0..<Int(buffer.frameLength) { let sample = Double(samples[i]); energy += sample * sample }
                let level = 20 * log10(max(0.00001, sqrt(energy / Double(buffer.frameLength))))
                let now = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { guard let self, self.listening, !self.finalizingSpeech, round == self.recognitionRound else { return }
                    if self.turnDetector.feed(levelDB: level, now: now, hasTranscript: !self.latestTranscript.isEmpty) { self.finishSpeechInput(round) }
                }
            }; tapInstalled = true
            speechTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async { guard let self, self.listening, round == self.recognitionRound else { return }
                    if let result { let text = result.bestTranscription.formattedString
                        self.latestTranscript = text
                        if result.isFinal { self.commitSpeech(text) }
                        else { self.event(["type": "partial", "token": self.recognitionToken, "text": text]) }
                    }
                    if let error, self.listening {
                        if self.finalizingSpeech, !self.latestTranscript.isEmpty { self.commitSpeech(self.latestTranscript) }
                        else { self.stopRecognition(); self.event(["type": "asrError", "token": self.recognitionToken, "message": "音声認識が停止しました: " + error.localizedDescription]) }
                    }
                }
            }
            audioEngine.prepare(); try audioEngine.start(); reply(id, true)
            let timeout = DispatchWorkItem { [weak self] in guard let self, self.listening, round == self.recognitionRound else { return }; if !self.latestTranscript.isEmpty { self.commitSpeech(self.latestTranscript) } else { self.stopRecognition(); self.event(["type": "asrIdle", "token": self.recognitionToken]) } }; speechTimeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
        } catch { stopRecognition(); reply(id, nil, error.localizedDescription) }
    }
    private func commitSpeech(_ text: String) {
        guard listening else { return }; let token = recognitionToken
        stopRecognition(); event(["type": "asrFinal", "token": token, "text": text])
    }
    private func finishSpeechInput(_ round: Int) {
        guard listening, !finalizingSpeech, round == recognitionRound else { return }
        finalizingSpeech = true
        speechTimeout?.cancel()
        audioEngine.stop()
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        speechRequest?.endAudio()
        let finalTimeout = DispatchWorkItem { [weak self] in
            guard let self, self.listening, round == self.recognitionRound else { return }
            self.commitSpeech(self.latestTranscript)
        }
        speechTimeout = finalTimeout; DispatchQueue.main.asyncAfter(deadline: .now() + finalWait, execute: finalTimeout)
    }
    private func stopRecognition() { listening = false; recognitionRound += 1; speechTimeout?.cancel(); speechTimeout = nil; audioEngine.stop(); if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }; speechRequest?.endAudio(); speechTask?.cancel(); speechTask = nil; speechRequest = nil }
    @objc private func closeChat() { chatPanel.isHidden = true }
    @objc private func reloadChat() { chat.reload() }
    @objc private func attachChat() {
        guard chat.url?.scheme == "https", chat.url?.host == "chatgpt.com" else {
            notice("ChatGPTへのログインを完了してください。外部ブラウザーのログイン状態はアプリに引き継がれません。"); return
        }
        chat.evaluateJavaScript("window.LiveTalkMobileChat ? LiveTalkMobileChat.arm() : ({ok:false,message:'ChatGPTを読み込み中です。再読込してお試しください。'})") { [weak self] result, error in
            guard let self else { return }
            let status = result as? [String: Any]
            if status?["ok"] as? Bool == true { self.chatPanel.isHidden = true; self.chatLabel.text = "接続済み" }
            else { let text = status?["message"] as? String ?? "接続を確認できません。再読込するか、ChatGPTの返答をコピーして読み上げてください。"; self.chatLabel.text = text; self.notice(text) }
        }
    }
    private func notice(_ text: String) { let alert = UIAlertController(title: "確認", message: text, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true) }
    private func chatCommand(_ id: Int, method: String, text: String) {
        guard experimentalAllowed else { reply(id, nil, "この配布版は貼り付け読み上げ専用です。"); return }
        guard text.utf16.count <= 12000 else { reply(id, nil, "質問が長すぎます。12,000文字以内にしてください。"); return }
        guard chat.url?.host == "chatgpt.com", chat.url?.scheme == "https" else { reply(id, nil, "ChatGPTを開いて、使うチャットを接続してください"); return }
        chatRequests.insert(id)
        chat.evaluateJavaScript("(async()=>{try{if(!window.LiveTalkMobileChat)throw Error('ChatGPTを接続してください');await LiveTalkMobileChat.\(method)(\(js(text)));window.webkit.messageHandlers.chatEvent.postMessage({type:'ack',id:\(id)});}catch(e){window.webkit.messageHandlers.chatEvent.postMessage({type:'ack',id:\(id),error:e.message});}})()", completionHandler: { [weak self] _, error in
            guard let self, error != nil, self.chatRequests.remove(id) != nil else { return }
            self.reply(id, nil, "ChatGPT画面の操作に失敗しました。再読込して接続し直してください。")
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in guard let self, self.chatRequests.remove(id) != nil else { return }; self.reply(id, nil, "ChatGPTの操作を確認できませんでした。ChatGPT画面を確認してください") }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if webView === app { loaded = true; fontChanged(); commerceChanged(); confirmIncoming() } else { chatLabel.text = "入力欄が表示されたら「接続する」"; event(["type": "chatLoaded"]) } }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { if webView === chat { chatLabel.text = "読み込み中…"; event(["type": "detached", "quiet": true, "message": "ChatGPTを読み込み中です"]) } }
    private func chatHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return ["chatgpt.com", "auth.openai.com", "auth0.openai.com", "accounts.google.com", "appleid.apple.com", "account.apple.com", "login.microsoftonline.com", "login.live.com"].contains(host) || host.hasSuffix(".auth.openai.com")
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if webView === app { decisionHandler(LocalBridgePolicy.allowed(url, index: indexURL) ? .allow : .cancel); return }
        if chatHost(url) { decisionHandler(.allow) }
        else {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated, url.scheme == "https" { UIApplication.shared.open(url) }
            else if action.targetFrame?.isMainFrame != false { chatLabel.text = "ログイン先を開けません。ChatGPTアプリの返答をコピーして読み上げられます。" }
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil, let url = action.request.url, chatHost(url) { chat.load(action.request) }
        return nil
    }
    private func chatFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        chatLabel.text = "読み込みに失敗しました。「再読込」をお試しください。"
        event(["type": "connectionError", "message": "ChatGPTに接続できません。インターネット接続を確認して再読込してください。"])
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === chat { chatFailed(error) } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === chat { chatFailed(error) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === chat { event(["type": "detached", "message": "ChatGPT画面が終了しました。開き直して接続してください"]) }; webView.reload() }
    private func export(_ id: Int, settings: Any) { do {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("livetalk-settings.json"); try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil); sheet.popoverPresentationController?.sourceView = view; sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 20, width: 1, height: 1); present(sheet, animated: true); reply(id, true)
    } catch { reply(id, nil, error.localizedDescription) } }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let id = documentId else { return }; documentId = nil
        do { guard let url = urls.first else { throw MobileError.message("cancelled") }; let accessing = url.startAccessingSecurityScopedResource(); defer { if accessing { url.stopAccessingSecurityScopedResource() } }; let data = try Data(contentsOf: url); if data.count > 65536 { throw MobileError.message("設定ファイルが大きすぎます") }; reply(id, try JSONSerialization.jsonObject(with: data)) } catch { reply(id, nil, error.localizedDescription) }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { if let id = documentId { reply(id, nil, "cancelled") }; documentId = nil }
    @objc private func fontChanged() { event(["type": "fontScale", "scale": Double(UIFont.preferredFont(forTextStyle: .body).pointSize / 17)]) }
    @objc private func incomingURL(_ notification: Notification) { if let url = notification.object as? URL { acceptIncomingURL(url) } }
    func acceptIncomingURL(_ url: URL) {
        guard let text = IncomingText.parse(url) else { notice("文章を受け取れませんでした。文章をコピーして貼り付けてください。"); return }
        incoming = text; if loaded { confirmIncoming() }
    }
    private func confirmIncoming() {
        guard loaded, foreground, presentedViewController == nil, let text = incoming else { return }
        incoming = nil
        let alert = UIAlertController(title: "文章を受け取りました", message: String(text.prefix(120)) + (text.count > 120 ? "…" : ""), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel))
        alert.addAction(UIAlertAction(title: "読み上げ画面に入れる", style: .default) { _ in self.chatPanel.isHidden = true; self.event(["type": "sharedText", "text": text]) })
        present(alert, animated: true)
    }
    @objc private func background() { foreground = false; advertising.foreground = false; advertising.suspend(); generation += 1; if !ConversationRuntime.shared.carActive { gpt.stop() }; stopRecognition(); stopPlayer(); event(["type": "background"]) }
    @objc private func resume() { foreground = true; advertising.foreground = true; Task { await commerce.refreshEntitlements() }; if !ConversationRuntime.shared.carActive { event(["type": "foreground"]); restoreCarAnswer(); confirmIncoming() } }
    @objc private func routeChanged(_ notification: Notification) {
        guard (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, listening || player != nil || waitingVoice.active else { return }
        generation += 1; if !ConversationRuntime.shared.carActive { gpt.stop() }; stopRecognition(); stopPlayer(); event(["type": "routeLost"])
    }
    @objc private func audioInterrupted(_ notification: Notification) {
        if (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
            generation += 1; if !ConversationRuntime.shared.carActive { gpt.stop() }; stopRecognition(); stopPlayer(); event(["type": "audioInterrupted"])
        }
    }
}
