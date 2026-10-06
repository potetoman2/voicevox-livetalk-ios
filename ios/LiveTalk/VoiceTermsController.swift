import UIKit

final class VoiceTermsController: UIViewController {
    private let text: String
    private let requiresAcceptance: Bool
    private let heading: String
    private let introduction: String
    private var completion: ((Bool) -> Void)?
    init(text: String, requiresAcceptance: Bool, heading: String = "音声の利用条件", introduction: String = "VOICEVOX:四国めたん / ずんだもん / 春日部つむぎ / 雨晴はう\n音声を公開・販売する場合は、各音声の条件とクレジットをご確認ください。", completion: @escaping (Bool) -> Void) {
        self.text = text; self.requiresAcceptance = requiresAcceptance; self.completion = completion
        self.heading = heading; self.introduction = introduction
        super.init(nibName: nil, bundle: nil); isModalInPresentation = true
    }
    required init?(coder: NSCoder) { fatalError("Use text initializer") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let title = UILabel(); title.text = heading; title.font = .preferredFont(forTextStyle: .title2); title.adjustsFontForContentSizeCategory = true
        let intro = UILabel(); intro.text = introduction; intro.numberOfLines = 0; intro.font = .preferredFont(forTextStyle: .subheadline); intro.adjustsFontForContentSizeCategory = true
        let body = UITextView(); body.text = text; body.isEditable = false; body.isSelectable = true; body.font = .preferredFont(forTextStyle: .body); body.adjustsFontForContentSizeCategory = true; body.dataDetectorTypes = [.link]; body.backgroundColor = .secondarySystemBackground; body.layer.cornerRadius = 12
        let buttons = UIStackView(); buttons.axis = .horizontal; buttons.spacing = 12; buttons.distribution = .fillEqually
        let cancel = UIButton(type: .system); cancel.setTitle(requiresAcceptance ? "同意しない" : "閉じる", for: .normal); cancel.addTarget(self, action: #selector(cancelled), for: .touchUpInside); buttons.addArrangedSubview(cancel)
        if requiresAcceptance { let agree = UIButton(type: .system); agree.setTitle("確認して同意する", for: .normal); agree.addTarget(self, action: #selector(accepted), for: .touchUpInside); buttons.addArrangedSubview(agree) }
        buttons.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        let stack = UIStackView(arrangedSubviews: [title, intro, body, buttons]); stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12), stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)])
    }
    private func finish(_ agreed: Bool) { let callback = completion; completion = nil; dismiss(animated: true) { callback?(agreed) } }
    @objc private func cancelled() { finish(false) }
    @objc private func accepted() { finish(true) }
}
