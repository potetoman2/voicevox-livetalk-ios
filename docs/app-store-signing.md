# WindowsからのApp Store提出準備

2026-10-07。GitHubのMac実行環境でApple署名付きArchiveとIPAを作る工程を用意しました。**署名付きビルド・アップロード・審査申請は未実行**です。現在の評価版IPAは引き続き未署名です。

Apple Developer Programへの有効な個人加入、アプリ・商品の登録、販売契約・税務・銀行情報が必要です。本人情報はAppleの公式画面で入力します。App Storeの販売者名はAppleで確認した本名であり、公開窓口の屋号「ぞこーばスタジオ」と同一とは限りません。商用GPT連携の承認と本番接続、音声・プライバシー、実際の課金と広告の検証も残っています。準備JSONをtrueへ変更するだけでは完了しません。

## 署名情報の保管

所有者が証明書の保管と署名用アクセスを承認した後、リポジトリのSettings → Environmentsで `app-store-signing` を作り、本人による実行承認とmain限定のルールを設定します。ワークフローの環境名だけでは保護ルールは有効になりません。個人運営で別の承認者がいない場合、「自己承認禁止」によって実行不能にしないようにします。

環境Variablesに `APPLE_TEAM_ID`、Secretsに次の3項目を本人が登録します。値をチャット、ソース、ZIP、Issue、Actionsの実行入力へ貼らないでください。

| Secret名 | 内容 |
|---|---|
| `APPLE_DISTRIBUTION_P12_BASE64` | Apple Distribution証明書と秘密鍵を含むP12をBase64化した値 |
| `APPLE_DISTRIBUTION_P12_PASSWORD` | P12のパスワード |
| `APPLE_APP_STORE_PROFILE_BASE64` | 正確なLiveTalk Bundle ID用App StoreプロファイルをBase64化した値 |

証明書と鍵は所有者がAppleで作成・管理します。今回、証明書・APIキー・GitHub Secretsは取得や登録をしていません。アップロード用鍵は署名の3項目とは別です。

## 実行

Actions → **App Store preparation and signed export** → Run workflowで `inspect` を選ぶと、秘密情報なしで残件を確認します。検査の正常終了は「販売可能」という判定ではなく、報告の `ready` と残件を確認します。未完了なら署名のジョブを開始しません。

実際の許可・登録・検証が完了した後に `signed-export` を選びます。mainの同じリビジョンと公開条件を再検査してから署名情報を使います。一時Keychainと今回配置したプロファイルは終了時に除去します。別チーム・別アプリ・期限切れ・開発用・Ad Hoc・Enterprise・デバッグ可・未承認CarPlayのプロファイルを拒否します。原本や所有者名は検査の報告へ出力しません。

成功時のみ署名済みIPAとSHA256を1日保持の成果物へ保存します。P12・プロファイル原本・秘密鍵・Keychainは成果物に含めません。公開リポジトリのActions成果物の公開範囲は所有者が確認してください。未公開配布物を保存する場合は、その扱いを先に決めます。

この工程は**出力まで**です。Appleの対応する方法でApp Store Connectへアップロードし、Apple側の処理完了を確認してからTestFlightへ進みます。審査申請・ストア公開・課金有効化は別工程です。CarPlayは専用承認と署名の検証後に対応します。

[Appleのプロファイル](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)、[Appleのアップロード](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)、[GitHubの環境保護](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)。
