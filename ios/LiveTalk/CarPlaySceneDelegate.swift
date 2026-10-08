import CarPlay

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var controller: CPInterfaceController?
    private let conversation = CarConversation()
    private var voice: CPVoiceControlTemplate?
    private var leaving = false
    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        // CPInterfaceController is MainActor-isolated and Sendable in Apple's SDK.
        // Preserve callback order without accessing UI state on the caller thread.
        DispatchQueue.main.async { [weak self] in
            self?.connect(interfaceController)
        }
    }
    private func connect(_ interfaceController: CPInterfaceController) {
        controller = interfaceController; interfaceController.delegate = self
        guard Bundle.main.object(forInfoDictionaryKey: "LTCarPlayEnabled") as? Bool == true else { showError("CarPlay対応版の署名が必要です。"); return }
        guard #available(iOS 26.4, *) else { showError("CarPlayでの音声会話にはiOS 26.4以降が必要です。"); return }
        conversation.onState = { [weak self] state in self?.voice?.activateVoiceControlState(withIdentifier: state) }
        conversation.onError = { [weak self] message in self?.showError(message) }
        showVoice()
    }
    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        let controllerID = ObjectIdentifier(interfaceController)
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.controller, ObjectIdentifier(controller) == controllerID else { return }
            self.conversation.stop(); controller.delegate = nil; self.controller = nil; self.voice = nil
        }
    }
    private func showVoice() {
        guard let controller else { return }
        guard Bundle.main.object(forInfoDictionaryKey: "LTCarPlayEnabled") as? Bool == true else { showError("CarPlay対応版の署名が必要です。"); return }
        guard #available(iOS 26.4, *) else { showError("iOS 26.4以降が必要です。"); return }; leaving = false
        let labels = [("preparing", "準備しています", "waveform"), ("listening", "聞いています", "mic.fill"), ("thinking", "考えています", "ellipsis"), ("searching", "調べています", "magnifyingglass"), ("speaking", "返答しています", "waveform"), ("idle", "会話を終了しました", "pause.fill")]
        let states = labels.map { id, title, image in CPVoiceControlState(identifier: id, titleVariants: [title], image: UIImage(systemName: image)!, repeats: false) }
        let template = CPVoiceControlTemplate(voiceControlStates: states); voice = template
        // The selector gate permits the personal preview to compile with an older
        // SDK; voice-template navigation buttons are available from iOS 26.4.
        if template.responds(to: NSSelectorFromString("setTrailingNavigationBarButtons:")) {
            let interrupt = CPBarButton(title: "話す") { [weak self] _ in self?.conversation.interrupt() }
            let stop = CPBarButton(title: "終了") { [weak self] _ in self?.finish() }
            template.setValue([interrupt, stop], forKey: "trailingNavigationBarButtons")
        }
        controller.setRootTemplate(template, animated: false) { [weak self] success, _ in
            guard let self, self.controller === controller else { return }; if success { self.conversation.start() } else { self.showError("会話画面を表示できません。CarPlayの権限とiOSのバージョンを確認してください。") }
        }
    }
    private func finish() {
        leaving = true; conversation.stop(); voice = nil
        let button = CPGridButton(titleVariants: ["会話を再開"], image: UIImage(systemName: "mic.fill")!) { [weak self] _ in self?.showVoice() }
        controller?.setRootTemplate(CPGridTemplate(title: "LiveTalk", gridButtons: [button]), animated: true, completion: nil)
    }
    private func showError(_ message: String) {
        conversation.stop(); leaving = true
        let action = CPAlertAction(title: "閉じる", style: .default) { [weak self] _ in self?.controller?.dismissTemplate(animated: true, completion: nil); self?.finish() }
        let alert = CPAlertTemplate(titleVariants: [message], actions: [action])
        let button = CPGridButton(titleVariants: ["接続を確認"], image: UIImage(systemName: "mic.fill")!) { [weak self] _ in self?.showVoice() }
        controller?.setRootTemplate(CPGridTemplate(title: "LiveTalk", gridButtons: [button]), animated: false) { [weak self] _, _ in self?.controller?.presentTemplate(alert, animated: true, completion: nil) }
    }
    func templateWillDisappear(_ template: CPTemplate, animated: Bool) {
        if template === voice, !leaving { conversation.stop() }
    }
}
