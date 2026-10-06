# 販売前に残る事項
確認日：2026-10-06。2.1は音声会話の個人評価版です。

| 項目 | 状態 |
|---|---|
| 音声会話 | 端末内音声認識、ChatGPT公式ストリーミング、VOICEVOX短文合成、連続聞き取り、割り込みを実装。実機確認待ち |
| APIキー | 入力不要。内部ではOAuthと公式Responses APIを使用。完全なAPI通信なしではない |
| ChatGPT契約での接続 | 公開ソース・ローカルアプリ向けの公式方式。アカウントの対応・利用枠・同意が必要 |
| 販売版のChatGPT連携 | 有料・遠隔提供アプリはOpenAIへの申請が必要。許可取得は未完了。storeビルドでは無効 |
| 既存ChatGPTチャット | 履歴・メモリ・既存チャットは自動で引き継がない。アプリ内の新しい会話 |
| 実機 | 新しいログイン方式、音声、マイク、利用枠、応答時間、長時間使用は確認待ち |
| App Store | Apple Developer Program、販売者情報、署名、配布・審査が未完了 |
| 音声の条件 | 同梱モデルと各話者の現行条件・クレジットを販売者が確認する |
| 運営 | 公開プライバシーポリシー、連絡先、サポート体制、販売価格等が未設定 |
| Android | 今回の更新はiPhone。Androidネイティブ版は含まない |

[公式接続の対象と申請](https://developers.openai.com/siwc/token-sharing-open-source)、[対応範囲](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)。
[Apple Developer Program](https://developer.apple.com/programs/)、[Apple審査ガイドライン](https://developer.apple.com/app-store/review/guidelines/)。
[同梱音声モデルの条件](https://raw.githubusercontent.com/VOICEVOX/voicevox_vvm/0.16.0/README.md)。

音声・合成は端末内。質問と会話文脈をOpenAIへ送信します。接続情報はiPhoneのKeychain、設定はUserDefaults。会話本文は設定・診断へ保存しません。利用上限はChatGPTの設定へ案内します。
