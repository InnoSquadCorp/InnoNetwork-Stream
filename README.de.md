# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## Umfang

HLS-Parsing, begrenzte VOD-/Offline-Downloads, Live/DVR, native Wiedergabe-/FairPlay-Integration und dekodiertes Audio. Kein Player-UI, CDN, Transcoder oder DRM-Dienst. Wähle InnoNetwork-Stream oder die einzelnen Produkte InnoNetworkHLS, InnoNetworkHLSLive, InnoNetworkHLSAVFoundation und InnoNetworkHLSAudio. Diese vier Namen sind Swift-Module; InnoNetworkStream existiert nicht als Modul.

Die sieben Schnellstarts behandeln dieselbe stabile Version, Installation, Beispiele, Lebenszyklen und Migration. Der ausführliche englische Leitfaden dient als gemeinsame Referenz; die Übersetzungen wurden nicht als muttersprachlich geprüft ausgewiesen.

<!-- section:2 -->
## Voraussetzungen

Swift 6.2 oder neuer, Swift-6-Sprachmodus. Nur Apple: iOS 16+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1+. Core ist exakt auf InnoNetwork 6.1.1 festgelegt.

Dekodierte Audio-APIs benötigen zusätzlich Swift 6.4/Xcode 27 und unterstützte OS-27-APIs; prüfe die Verfügbarkeit je Symbol. Die Swift-6.2-Oberfläche ist nicht identisch. Alle sechs Makros nutzen werfende validated-Fabriken. configuration() startet keine Netzwerkarbeit.

<!-- section:3 -->
## Installation

Füge diese Paketabhängigkeiten und anschließend die Produkte dem verwendenden Target hinzu.

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## Schnellstart

Die Beispiele wurden mit dem Quellcode abgeglichen; sie belegen keinen neuen Build oder Gerätetest. URLs, Zugangsdaten und Transportrichtlinien gehören der Anwendung.

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
## Lebenszyklus und Fehler

Behalte das Handle. Das Abbrechen eines Beobachters oder receipt-Wartenden stoppt den Produzenten nicht; rufe cancel() auf oder leite den Task-Abbruch wie im Beispiel weiter. receipt() liefert das verbindliche Endergebnis; events() erlaubt bis zu 64 Abonnements mit je 16 neuesten Ereignissen und Sequenz-/Verlustmetadaten. Später Abbruch löscht keine fertige Ausgabe. Fange Fehler ab und verwende typisierte Fehlerverträge; protokolliere keine URLs, Zugangsdaten oder Medieninhalte.

Das asynchrone offline downloadPackage läuft im aufrufenden Task und übernimmt dessen Abbruch; start-Handles trennen Beobachtung und Abbruch. Native Hintergrundaufgaben behalten die Systemwiederherstellung. FairPlay-Zugangsdaten, Berechtigungen und Schlüsselspeicher gehören der Anwendung; eine Veröffentlichung zertifiziert keine Dienste oder Geräte.

<!-- section:6 -->
## Migration

Für alte Core-HLS-Produkte ergänze dieses Paket und behalte die einzelnen Imports. Beim unveröffentlichten InnoStream-Checkout ändere URL, Paketidentität und package:-Argumente. Alte öffentliche Tags oder Weiterleitungen werden nicht vorausgesetzt. Die Migration unterscheidet streamgebundene Downloads, gehaltene Handles und vom Parser erzeugte Playlist-Dokumente.

<!-- section:7 -->
## Dokumentation und Prüfung

Führe diese Prüfungen im Repository aus. Statische Prüfungen ersetzen weder Swift-Builds, Makroexpansion und DocC noch Geräte- oder Diensttests. Entferne INNONETWORK_LOCAL_PATH aus der Umgebung, um den veröffentlichten Abhängigkeitsgraphen zu prüfen.

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
