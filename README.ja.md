# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## 対象範囲

HLS 解析、上限付き VOD・オフライン取得、ライブ・DVR、ネイティブ再生・FairPlay 連携、デコード音声を提供します。プレイヤー UI、CDN、トランスコーダー、DRM サービスではありません。統合製品 InnoNetwork-Stream または個別製品 InnoNetworkHLS、InnoNetworkHLSLive、InnoNetworkHLSAVFoundation、InnoNetworkHLSAudio を選びます。Swift モジュールは後者の 4 つで、InnoNetworkStream モジュールはありません。

7 言語のクイックスタートは、同じ安定版の導入、例、ライフサイクル、移行を扱います。詳細な英語ガイドを共通の上級リファレンスとします。翻訳はネイティブ話者による確認を意味しません。

<!-- section:2 -->
## 動作要件

Swift 6.2 以降、Swift 6 言語モード。Apple 専用: iOS 16+、macOS 14+、tvOS 16+、watchOS 9+、visionOS 1+。Core は InnoNetwork 6.1.1 に厳密に固定されます。

デコード音声の宣言には追加で Swift 6.4/Xcode 27 と対応する OS 27 API が必要です。各シンボルの利用可能性を確認してください。Swift 6.2 の公開 API は同一ではありません。6 つのマクロはすべてエラーを送出する validated 設定ファクトリーを利用し、configuration() 自体は通信を開始しません。

<!-- section:3 -->
## インストール

以下のパッケージ依存関係を追加し、利用するターゲットに製品を追加してください。

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## クイックスタート

以下はソースと照合した例であり、新たなコンパイルや実機テストの結果ではありません。URL、認証情報、転送ポリシーはアプリが管理します。

```swift
import Foundation
import InnoNetworkHLS

@HLSDownloadDefinition(
    maximumMediaResourceBytes: 8_388_608,
    maximumTotalDownloadBytes: 268_435_456,
    maximumConcurrentResourceTransfers: 3
)
enum MovieDownload {}

func saveMovie(source: URL, destination: URL) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(
        sourceURL: source,
        destinationURL: destination
    )
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}
```

<!-- section:5 -->
## 所有権とエラー

操作ハンドルを保持してください。観察者や receipt 待機のキャンセルは処理を停止しません。cancel() を明示的に呼ぶか、例のようにタスクのキャンセルを伝えます。receipt() が確定結果です。events() は最大 64 購読で、それぞれ最新 16 イベントと順序・欠落情報を保持します。遅いキャンセルで完成済み出力は削除されません。呼び出し側でエラーを処理し、型付き失敗契約を利用してください。URL、認証情報、メディア内容をログに残さないでください。

非同期のオフライン downloadPackage は呼び出しタスクで動作し、そのキャンセルを継承します。明示的な start ハンドルでは観察とキャンセルが分離されています。ネイティブのバックグラウンド処理はシステム復元に従います。FairPlay 認証情報、権限、鍵保存はアプリの責務であり、ライブラリ公開はサービス・実機認証ではありません。

<!-- section:6 -->
## 移行

旧 Core HLS 製品からは本パッケージを追加し、個別 import を維持します。未公開 InnoStream チェックアウトからは URL、パッケージ識別子、製品の package: 引数を更新してください。旧公開タグやリダイレクトは仮定しません。移行ガイドはストリーム所有の旧ダウンロード、現在の保持ハンドル、パーサー生成のプレイリスト文書を区別します。

<!-- section:7 -->
## ドキュメントと検証

これらのチェックは本リポジトリで実行します。静的チェックは Swift ビルド、マクロ展開、DocC、実機・サービス検証の代わりにはなりません。公開済み依存グラフの検証時は INNONETWORK_LOCAL_PATH を解除してください。

- [Technical guide (English)](docs/GUIDE.md)
- [Documentation map / historical evidence](docs/README.md)
- [Migration (English)](docs/MACRO_FIRST_MIGRATION.md)
- [API stability](API_STABILITY.md)
- [AI development skill](skills/README.md)
- [Release qualification record](docs/releases/6.1.1.md)
- [Roadmap](docs/ROADMAP.md)
- [MIT License](LICENSE)

```bash
bash Scripts/validate_docs_release_state.sh
python3 Scripts/check_readme_parity.py
env -u INNONETWORK_LOCAL_PATH bash Scripts/swiftpm.sh test --force-resolved-versions --parallel
```
