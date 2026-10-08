# LiveTalk 2.7 — 終了通知とビルド環境の保守

2026-10-08。公開準備版。GPT接続、実課金、収益広告、CarPlayの配布許可は有効化していない。2.6の検証済みZIP・IPAと既存のiPhoneアプリは保全する。

- AVFoundationの終了／デコード失敗を、Sendableな値だけを渡してMainActorへ配送する。プレイヤーごとのUUIDとdelegateの保持により、停止・新しい再生の後の旧通知が新しい再生を終了しない。
- Safariの終了通知はログイン試行ごとのcallbackにする。MainActorへ配送した時点でも元の試行番号を確認し、遅いキャンセルで別のログインを取り消さない。
- CarPlayのscene通知をメインキューへ配送し、切断時は対象controllerの一致を確認する。Apple SDKでMainActor/Sendableと宣言されているCPInterfaceControllerだけを配送する。車載実機の検証は未実施で、CarPlayは無効のまま。
- BluetoothのHFPルーティング指定をSDKの現行名allowBluetoothHFPへ更新する。
- GitHub Actionsのcheckout/setup-python/setup-node/upload-artifactを公式のNode24対応v6の固定commitへ更新する。認証情報のcheckout保存は引き続き無効。
- Apple simulatorテストへ終了通知の3試験を追加する。ワーカースレッドからの音声終了・デコード失敗がメインスレッドへ配送され、Safari終了通知が同期的に状態を変更しないことを確認する。実音声再生・実ログイン・実機の代用ではない。

実施結果・成果物のSHA256は、Macビルド完了後に成果物の検証レポートへ記録する。ソース作成段階ではコンパイル成功を推定しない。2.0までの過去20回の改善記録とは別の保守作業である。

販売の残件は[2.6監査](sales-audit-2.6.md)と[実機検証票](release-device-tests.md)を継続管理する。承認待ちを確認済みに変更せず、正式な商用接続の許可と実装・音声規約の適用確認・Apple契約/登録商品・実機試験が揃うまで販売を開始しない。

参照: [Apple CPInterfaceController](https://developer.apple.com/documentation/carplay/cpinterfacecontroller)、[Bluetoothの同等性に関するApple回答](https://developer.apple.com/forums/thread/797379)、[Swiftのdata race safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/)、各[GitHub Actions公式リリース](https://github.com/actions/checkout/releases)。
