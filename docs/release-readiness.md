# 販売前に残る事項

確認日：2026-10-07。2.4は個人向け公開準備版です。運営者の屋号は **ぞこーばスタジオ**、窓口は **doude424@gmail.com**。広告付き無料版と広告除去980円の買い切りを予定しています。App Store公開は未完了です。[手続きの記録](../release/publication-progress.json)。

| 項目 | 確認できたこと／残件 |
|---|---|
| 音声会話・検索 | 2.2は利用者から応答速度と検索が良好との報告。2.4の販売向け実機試験は未完了 |
| APIキー | 入力不要。内部ではOAuthと公式APIを使用。完全なAPI通信なしではない |
| 商用GPT連携 | 2026-10-07に申請受付を確認。承認と本番接続の実装・検証は未完了 |
| 既存チャット | 履歴・メモリは自動で引き継がず、アプリ内の新しい会話 |
| ビルド | Xcode 26.3・iOS 26.2 SDKでiPhone用未署名IPAをコンパイル済み。署名付きArchiveは未作成 |
| 課金 | StoreKit Testingの7件合格。登録した本番商品・実際のSandbox購入と復元は未検証 |
| 広告 | 公式テストIDと同意・権利・画面状態による制御を実装。本番ID・契約・実際の通信検証は未完了 |
| 紹介とサポート | [公開サイト](https://potetoman2.github.io/)と準備版のデータ説明・利用条件を公開。正式な提供条件の確定は未完了 |
| Apple | Web登録の読み込み問題があり、公式iPhoneアプリでの加入を案内。加入の有効化、契約・銀行・税務・アプリと商品登録は未確認 |
| 音声の条件 | CORE・VVM・同梱話者の公式条件とクレジットを確認・同梱。販売版の話者と用途の最終確認は未完了 |
| セキュリティ | 秘密情報検査、接続・Web画面・購入・広告開始を制御。販売環境の最終通信・実機確認は未完了。独立した侵入試験は未実施 |
| 署名と提出 | [Mac実行環境での署名付き出力](app-store-signing.md)を準備。公開条件を通過しなければ署名を開始しない。アップロード・TestFlight・審査・販売開始は未実行 |
| CarPlay | 専用承認と車載実機検証が未完了。対応済みとして掲載しない |
| Android | 今回はiOS版。Androidの販売用ネイティブ課金・広告は含まない |

マイク・音声合成は端末内で処理し、質問と会話文脈を同意後にOpenAIへ送信します。接続情報はKeychain、設定はUserDefaults。会話本文は設定・診断へ保存しません。公開準備版の購入・収益広告は無効です。チェック表は許可証、契約、Appleの審査結果や安全の保証ではありません。

[公式接続の対象と申請](https://developers.openai.com/siwc/token-sharing-open-source)、[Appleの提出手順](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)、[同梱モデルの条件](https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/0.16.0/README.md)。
