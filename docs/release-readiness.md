# 販売前に残る事項
確認日：2026-10-06。2.3は公開準備を進めた個人評価版です。[収益化と権利の確認](commercial-preparation.md)。

| 項目 | 状態 |
|---|---|
| 音声会話 | 2.2は利用者が応答速度と検索に問題なしと報告。2.3の待機音声・同意・削除は実機確認待ち |
| APIキー | 入力不要。内部ではOAuthと公式Responses APIを使用。完全なAPI通信なしではない |
| ChatGPT契約での接続 | 公開ソース・ローカルアプリ向けの公式方式。アカウントの対応・利用枠・同意が必要 |
| 販売版のChatGPT連携 | 有料・遠隔提供アプリはOpenAIへの申請が必要。許可取得は未完了。storeビルドでは無効 |
| 既存ChatGPTチャット | 履歴・メモリ・既存チャットは自動で引き継がない。アプリ内の新しい会話 |
| 実機 | 2.2の基本会話・検索は利用者報告あり。2.3の追加機能・長時間試験・販売版の試験は未完了 |
| App Store | Apple Developer Program、販売者情報、署名、配布・審査が未完了 |
| 音声の条件 | CORE・VVM・4話者の公式条件を確認。通知は同梱、クレジット表示あり。有料汎用会話の権利レビューを完了した状態ではない |
| 運営 | アプリ内データ説明・同意・撤回・削除は追加済み。販売者と公開連絡先は未定。公開政策URL・価格・サポート・課金は未設定 |
| セキュリティ | 受信元限定・音声保護・秘密検査・ビルド依存固定を追加。独立した侵入試験は未実施 |
| 公開用ビルド | 未完了事項を検査し停止する。準備JSONの真偽欄は許可証の代わりにはならない |
| Android | 今回の更新はiPhone。Androidネイティブ版は含まない |

[公式接続の対象と申請](https://developers.openai.com/siwc/token-sharing-open-source)、[対応範囲](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)。
[Apple Developer Program](https://developer.apple.com/programs/)、[Apple審査ガイドライン](https://developer.apple.com/app-store/review/guidelines/)。
[同梱音声モデルの条件](https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/0.16.0/README.md)。

音声・合成は端末内。質問と会話文脈をOpenAIへ送信します。接続情報はiPhoneのKeychain、設定はUserDefaults。会話本文は設定・診断へ保存しません。利用上限はChatGPTの設定へ案内します。
