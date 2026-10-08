# App Store申請用の情報

2026-10-08。個人向け、広告付き無料／広告除去980円の買い切り。App Store申請・公開は未完了です。公開サイトのURLを記録しました。運営者の屋号は「ぞこーばスタジオ」。正式接続の許可、AppleとAdMobの登録、正式なプライバシー・利用条件、課金・広告の実機検証を確定してから提出します。

## 掲載内容の文案

名称案：LiveTalk（名称の空き・商標は登録時に確認）

紹介文：好きな声で、気軽におしゃべり。声で質問すると、返答ができた短い文から読み上げます。調べものの待ち時間は声で知らせ、参照したページも確認できます。話す速さ、声の高さ、抑揚、会話のテンポを自分好みに調整できます。

通常の会話機能は無料で利用できます。設定画面に広告を表示し、アプリ内の一度の購入で広告を外せます。ChatGPTの対応アカウント・利用枠・接続許可が必要です。広告除去にはAIの無制限利用やChatGPTのプラン料金は含まれません。既存チャットの履歴は自動では引き継ぎません。

音声：VOICEVOX Nemo（女性6声・男性3声）

2.8のNemoモデル・条件・クレジットを完成IPAで照合済みです。実機発声は別途確認します。OpenAI・VOICEVOXの公式製品や提携製品とは表示しません。CarPlayを審査・掲載するのは権限と実車試験の後です。「人間と同じ応答速度」「完全匿名」「全GPTモデル・全アカウント対応」「無制限」とは宣伝しません。

## 商品の登録票

| 項目 | 値 |
|---|---|
| 販売者 | 個人。本名はAppleで本人確認して登録。確認待ち |
| サポートメール | doude424@gmail.com |
| 本体価格 | 無料 |
| アプリBundle ID案 | jp.livetalk.mobile |
| 購入タイプ | 非消耗型（Non-Consumable） |
| 参照名 | LiveTalk Remove Ads |
| 商品ID | jp.livetalk.mobile.remove_ads |
| 表示名 | 広告を外す |
| 説明 | 一度の購入で広告を除去します。会話機能は無料版と同じです。 |
| 日本向け希望価格 | 980円。登録画面の価格点を確認し、別の額へ変更する場合は所有者へ確認 |
| Family Sharing | 初回は有効化しない。後で権利・実機確認を終えて選択 |
| サポートURL | https://potetoman2.github.io/support.html |
| マーケティングURL | https://potetoman2.github.io/ （app-ads.txtの発行元ドメインと一致させる） |
| プライバシー説明URL | https://potetoman2.github.io/privacy.html （準備版・正式文書への更新が必要） |
| 利用条件URL | https://potetoman2.github.io/terms.html （準備版・正式文書への更新が必要） |

価格はStoreKitの `Product.displayPrice` を表示。再購入防止、未確認の権利は解除しない、購入復元、保護者承認待ち、返金・権利取り消しに対応します。AppleのSandboxで確認してから商品を審査へ提出します。[非消耗型の登録](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)、[価格の設定](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/)。

## App Privacy確認票

| 情報 | 処理・提供先 | 確認事項 |
|---|---|---|
| マイク・合成音声 | iPhone内 | 生音声がOpenAI・Googleへ渡らないことを通信検証 |
| 質問・返答・検索語 | OpenAI、会話文脈はアプリのメモリー | 正式契約・保存期間・コンテンツと検索の申告 |
| OpenAI名・ID・端末登録ID | OpenAIと端末Keychain | 氏名・ユーザーID・端末IDの必要性・関連付け |
| 広告のIP・端末ID・操作・診断 | Google Mobile Ads / UMP | SDKのマニフェストを含むPrivacy Report、地域別同意、追跡の実態、国外処理 |
| 購入情報 | Apple StoreKit、端末の検証済み権利 | カードや認証情報は受け取らず、取引原文はログ・Web画面へ渡さない |
| サポートメール | 利用者が送った時だけ運営窓口 | 問い合わせ内容の保管と削除・権利対応の運用を確定 |

SDKは一般用のマニフェストでDevice IDのTrackingを宣言しています。アプリの広告最適化無効・IDFA許可なしだけを根拠に、全SDKに追跡がないと断定しません。実装設定・実通信・Appleの定義を確認して申告します。ベンダーのマニフェストを削って「収集なし」に見せません。[Appleの申告](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)、[Googleの申告](https://developers.google.com/admob/ios/privacy/data-disclosure)。

2026-10-09追加：`scripts/audit_ipa_privacy.py`で提出対象IPAからアプリ・各SDKの申告と同梱ライセンスを読み取る。申告の出所、関連付け・追跡の違い、対象IPAのSHA256を保持する。2.8の未署名IPAは3マニフェスト・10種類の情報を含む。SDKの端末ID追跡申告が残っているため、本番通信・契約・ATTの要否を確認するまで最終ラベルを確定しない。公式SDKの一般的な申告を、実際に送信済みという証拠とも扱わない。

Googleの発行元確認には、ストア掲載のマーケティングURLが必要。サポートURLの登録だけで代用したと考えない。公開後に「デベロッパのWebサイト」リンクとGoogleの検証結果を確認する。[Googleの設定手順](https://support.google.com/admob/answer/9363762?hl=ja)。

## 審査メモの文案

Native Japanese on-device speech recognition and VOICEVOX synthesis provide the main functionality. The text-only AI connection uses a separately approved commercial authorization. The app asks for explicit third-party AI data-sharing consent. A non-consumable StoreKit purchase removes settings-page banner ads only; the conversation features are identical in the free app. Ads are disabled during conversation, CarPlay, purchases and background. Advertising consent can be declined without blocking conversation. Tokens and raw StoreKit transactions are never exposed to the local web UI. No legacy ChatGPT website automation is enabled.

上の商用接続が実際に承認・実装されるまでは提出しません。審査員がログインと会話・購入を確認できる方法をOpenAIとAppleの条件に従って用意します。評価版の「課金不可」を販売版の審査画面に残しません。

## 公開前の検証

購入・復元・再インストール・返金・保護者承認・未検証の取引・オフライン、広告同意の拒否と撤回、購入済み起動時に広告SDKを開始しないこと、広告中の会話開始、バックグラウンドと復帰を実機で確認します。Appleの年齢区分質問に実態で回答し、Kidsカテゴリは選択しません。EU等に提供する場合は対象地域ごとの販売者開示・トレーダー情報等を確認します。
