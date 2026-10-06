# CarPlay対応の準備

現在の配布IPAは無料Apple AccountでiPhoneに更新できる個人評価版です。車のCarPlay画面には表示されません。

## Appleの承認後に有効にする

1. Apple Developerの[CarPlayページ](https://developer.apple.com/carplay/)から音声会話アプリの権限を申請する。機能説明、音声会話を主用途にすること、画面設計を提示する。
2. 許可されたApp IDに音声会話のCarPlay権限を有効にし、新しいプロビジョニングプロファイルを作る。
3. iOS 26.4以上を使用し、承認済みの署名環境で `LIVETALK_CARPLAY=approved LIVETALK_DISTRIBUTION=preview bash scripts/build_ios_cloud.sh` として未署名の評価ビルドを作り、対応プロファイルで署名する。このコマンド自体は署名やAppleの承認を行わない。
4. 先にiPhoneで音声の準備・ChatGPTログイン・マイクと音声認識の許可を完了する。運転前に設定を済ませる。
5. 車に接続し、LiveTalkを開く。起動後は聞き取り→返答→聞き取りを繰り返す。「話す」で途中の返答を止めて聞き取り、「終了」または聞き取り中の「会話終了」で終了する。

販売版では、公開ソース評価版用の接続許可をそのまま有料サービスへ流用しない。`store` ビルドは現在ChatGPT連携を無効にしており、CarPlay側からも迂回しない。正式な商用接続の申請と設定が必要。

## 実機で確認する事項

CarPlay単独起動、iPhoneがロックされた状態、接続解除、着信、他の車載音声、音量、車のマイク、長い検索待ち、返答の割り込み、再開・終了を確認する。実測値と不具合を記録し、合格するまでCarPlay対応製品として販売しない。

車のスピーカーでは返答中のマイクを止める。返答への音声だけの割り込みは未対応で、「話す」ボタンで割り込む。自分のVOICEVOX音声を次の質問として拾うことを避けるための動作。

CarPlayで検索した直近の返答と参照リンクはメモリー内に保持し、iPhone画面に戻ったときに表示する。音声・会話・出典をファイルに保存しない。再起動後は残らない。

KeychainはCarPlayのロック中利用に必要な `AfterFirstUnlockThisDeviceOnly` を使用する。再起動後は一度iPhoneのロック解除が必要。トークンをWeb画面・設定ファイル・診断ログへ渡さない。

[Apple公式開発ガイド](https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf)に基づく。権限ファイルを作っただけではCarPlayは利用可能にならない。
