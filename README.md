# VOICEVOX LiveTalk — Windowsから作るiPhone版

Windows PCからGitHub ActionsのMacにコンパイルを依頼し、署名なしIPAを取得する開発用一式です。ご自身のMac・有料Apple Developer Program・GPT APIキーは前提にしません。VOICEVOXの合成はiPhone内で行う設計です。

**2026年10月3日、GitHub ActionsのMacでiPhone用IPAのコンパイル・生成に成功しました。** [成功したビルド #3](https://github.com/potetoman2/voicevox-livetalk-ios/actions/runs/37070796107)。対象ソース: `24efb2aab13e2c40bb13125f6f5631de0952d6b4`。このZIPは再ビルド用ソースです。アプリを入れる場合は `VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa` を使ってください。iPhoneへの署名・インストール・実機動作は未検証です。

## Windowsのブラウザーからビルド

1. [作成済みリポジトリ](https://github.com/potetoman2/voicevox-livetalk-ios)を使用できます。ご自身で新しく作る場合、公開リポジトリでは標準のMacランナーを無料で使えますが、ソースが公開されます。非公開ではアカウントの無料枠・課金設定を確認してください。
2. このフォルダーの中身をリポジトリ直下へアップロードします。`ios`・`shared`・`native`・`scripts`・`tests` と `.github/workflows/build-ios.yml` が直下に必要です。モデルやSDKをWindowsからアップロードする必要はありません。
3. Actions →「Build iOS IPA for Windows」→ Run workflow。mainへの最初のソースアップロードでもビルドが始まります。
4. 成功した実行のArtifactsから `LiveTalk-iOS-unsigned` をダウンロード・展開します。中に `VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa` ができます。
5. WindowsのPowerShellで `(Get-FileHash .\VOICEVOX_LiveTalk_iOS_UNSIGNED.ipa -Algorithm SHA256).Hash` を実行し、同梱 `.ipa.sha256` と照合します。

この経路にはGitHubのアカウントが必要です。クラウドへ送るのはこのアプリのソースとビルド設定です。Apple Accountのパスワード、証明書、ChatGPTのログイン情報や会話ログは送信しません。ビルド時に公式VOICEVOXライブラリ・辞書・音声モデルをダウンロードします。ダウンロード元とSHA-256をビルド成果物に記録します。

## WindowsのPowerShellから開始・取得する場合

この節はブラウザー操作の代わりです。公式GitHub CLIを入れて `gh auth login --web` を行った後、アップロード済みリポジトリを指定します。GitHub CLIの導入・認証は自動実行しません。

```powershell
./scripts/build_ios_windows.ps1 -Repository potetoman2/voicevox-livetalk-ios
```

既存の成功した実行から取得する場合：

```powershell
./scripts/build_ios_windows.ps1 -Repository potetoman2/voicevox-livetalk-ios -DownloadOnly -RunId 37070796107
```

成功したIPAを `ios-artifacts/<RunId>` に取得し、チェックサムを検証します。失敗した実行を成功として扱う処理はありません。`LiveTalk-iOS-build-log` にコンパイルログを保存します。

## 無料Apple AccountでiPhoneに入れる

署名なしIPAは、Safariから開くだけではインストールできません。**AltStore Classic + AltServer for Windowsで、ご自身の端末用に署名してインストールする経路**を使います。こちらのインストール作業は未検証です。

1. [AltStoreのWindows公式手順](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)に従ってAltServer・AppleのWindows用ソフトウェアを準備します。
2. iPhoneをWindowsに接続し、公式手順に従ってAltStore Classicを入れます。Appleのアカウント入力・端末の確認はご自身で行ってください。このチャットやGitHubへパスワードを貼り付ける必要はありません。
3. 作成したIPAをiPhoneの「ファイル」に転送し、AltStore ClassicのMy Appsから追加します。
4. 無料の署名は7日で期限切れになります。AltServerに接続して期限内に更新します。無料アカウントには同時に有効なアプリ数などの制限もあります。詳しくは[AltStoreの案内](https://faq.altstore.io/altstore-classic/your-altstore)をご確認ください。

**通話中のPC接続は不要ですが、初回導入と定期的な署名更新にはWindowsが必要です。** 無料のApple Accountで、更新不要のApp Store/TestFlight配布ができるとする説明はしません。

## アプリの使い方

iOS 16.4以降を対象とします。起動後、準備・ログ → 音声を準備 → 利用条件の確認 → 声を試す。

通話 → ChatGPTを開く → ログインして既存チャットを表示 → このチャットで通話 → 話しかける。

話速・声の高さ・抑揚・音量・間・人格プリセット・設定JSONの保存/読込があります。認識の途中経過を表示し、GPTの返答を短文から読み上げます。スピーカー使用中は返答の再生中にマイクを止め、イヤホン使用時は割り込み用の認識を選べます。

ChatGPTの自動連携はアプリ内WebViewの公開DOMを使います。埋め込みログインの制限・認証方式・画面変更によって動作しない場合があります。公式のChatGPT連携ではありません。その場合は普段のChatGPTアプリの返答をコピーし、LiveTalkで貼り付けて読み上げられます。コピー方式は自動の双方向通話にはなりません。日本語の端末内認識が使えない端末では文字入力を使います。

## 検証範囲

Windowsで、共通の会話処理13テスト、IPA梱包処理6テスト、PowerShellの構文検査を実施済みです。IPA梱包テストには模擬バンドルを使います。模擬データをアプリ成果物として配布することはありません。

クラウド実行時はXcode 16.4でJavaScriptを組み込んだSwift/C++アプリをiPhone向けにコンパイルし、arm64 Mach-O実行ファイル・音声モデル・辞書・必要なフレームワークがそろった場合のみIPAを作ります。署名を省く設定は開発用IPAの作成だけに使い、iPhoneの署名検査を無効にするものではありません。署名なしIPAは端末用に署名してから使います。

Macでの19テストとXcodeビルドに成功し、生成したIPAをWindowsに取得しました。チェックサム・ZIPの破損検査・arm64実行ファイル・音声モデル・辞書・ライセンス・マイク/音声認識の許可説明・画面の初期設定を確認済みです。iPhone実機でのログイン・認識・合成・再生・割り込みは未検証です。

公式資料：[Xcodeの動作環境](https://developer.apple.com/xcode/system-requirements)、[GitHubのMacランナー](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[Appleの開発者アカウント](https://developer.apple.com/help/account/basics/about-your-developer-account)、[AltStore Windows導入](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)。
