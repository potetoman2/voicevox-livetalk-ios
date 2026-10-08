# 配布アプリのプライバシー申告の確認

2026-10-09。保存済みの2.8未署名IPAを検査。アプリの動作は変更していない。ストアへの提出・本番広告・課金は開始していない。

検査はIPAに含まれる3つのPrivacyInfo.xcprivacyを読み、10種類の情報の宣言を出所ごとに保存する。アプリ、Google Mobile Ads、User Messaging Platformの申告を合成して、SDKが宣言した追跡や関連付けを消さない。使用APIと理由コード、同梱ライセンスのSHA256、版・ビルド・有効化フラグを同じ対象IPAに結び付ける。暗黙の欠落を「false」と扱わず、不正な型、必須SDKマニフェストの欠落、重複ファイル、不正なZIPパスを拒否する。アーカイブは展開しない。

対象IPAのSHA256：b19bcf9750f9f82164467dfb623e39668b9273f9a6bf0d661ba6ec452518566c

## 判明したこと

- アプリ本体は追跡なしを宣言している。
- Google Mobile Adsの一般的なSDK宣言には端末IDの追跡用途がある。アプリの広告最適化無効・IDFA許可なしを根拠に、この宣言を削除したり、実際の広告通信を調べずに「追跡なし」と登録しない。
- UMPはおおまかな位置、性能、操作情報をアプリ機能の目的で宣言している。
- GPT利用、購入、本番広告、実験接続、CarPlayの配布フラグはすべてfalse。

SDKの一般的な宣言は、設定後にその情報が送信されたという証拠ではない。最終的なApp Privacy回答は正式な接続と広告構成を確定し、実機の通信、関連付け、追跡とATTの要否、国外処理の条件を確認して決める。マニフェストの集計で実機試験や法的判断を済ませたと考えない。

## 提出時に使う検査

`python scripts/audit_ipa_privacy.py <提出対象.ipa> --output <検査.json>`

未署名ビルドと署名済みエクスポートの両方で実行し、対象IPAのSHA256付きの結果を保存する。署名前の報告を提出する署名済みアプリの証拠として使い回さない。CIに9件の検査テストを追加した。

ストアのマーケティングURLには https://potetoman2.github.io/ を登録する。Googleのapp-ads.txt確認ではこの掲載ドメインを使用するため、サポートURLだけを登録して完了と扱わない。

参照：[Appleのプライバシー要件](https://developer.apple.com/app-store/review/guidelines/#privacy)、[Googleのデータ申告](https://developers.google.com/admob/ios/privacy/data-disclosure)、[Googleの発行元設定](https://support.google.com/admob/answer/9363762?hl=ja)。
