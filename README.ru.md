# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## Возможности

Разбор HLS, ограниченные VOD/offline-загрузки, live/DVR, нативная интеграция воспроизведения/FairPlay и декодированное аудио. Это не интерфейс плеера, CDN, транскодер или DRM-сервис. Выберите InnoNetwork-Stream либо отдельные продукты InnoNetworkHLS, InnoNetworkHLSLive, InnoNetworkHLSAVFoundation и InnoNetworkHLSAudio. Эти четыре имени — модули Swift; модуля InnoNetworkStream нет.

Семь кратких руководств охватывают одну стабильную версию, установку, пример, жизненный цикл и миграцию. Подробное руководство на английском остаётся общей справкой; перевод не означает проверку носителем языка.

<!-- section:2 -->
## Требования

Swift 6.2+, языковой режим Swift 6. Только Apple: iOS 16+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1+. Core закреплён строго на InnoNetwork 6.1.1.

Декодированное аудио дополнительно требует Swift 6.4/Xcode 27 и поддерживаемых API OS 27; проверяйте доступность символов. Набор API Swift 6.2 отличается. Все шесть макросов используют выбрасывающие ошибки фабрики validated; configuration() не начинает сетевую работу.

<!-- section:3 -->
## Установка

Добавьте зависимости пакетов, затем продукты в использующий их target.

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## Быстрый старт

Примеры сверены с исходным кодом, но это не результат новой компиляции или теста на устройстве. URL, учётные данные и политики транспорта принадлежат приложению.

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
## Жизненный цикл и ошибки

Сохраняйте handle операции. Отмена наблюдателя или ожидания receipt не останавливает производителя; вызывайте cancel() явно либо передавайте отмену задачи, как в примере. receipt() определяет итог; events() допускает до 64 подписок, каждая хранит последние 16 событий с метаданными порядка и потерь. Поздняя отмена не удаляет готовый результат. Обрабатывайте ошибки по типизированным контрактам; не записывайте URL, учётные данные или медиаданные в журнал.

Асинхронный offline downloadPackage работает в вызывающей задаче и наследует её отмену; handles start разделяют наблюдение и отмену. Нативные фоновые задачи сохраняют системное восстановление. Данные доступа FairPlay, права и хранилище ключей принадлежат приложению; публикация библиотеки не сертифицирует устройства или сервисы.

<!-- section:6 -->
## Миграция

При переходе со старых HLS-продуктов Core добавьте этот пакет, сохранив отдельные imports. Для неопубликованного checkout InnoStream обновите URL, идентификатор пакета и аргументы package: продукта. Не предполагайте наличие старых публичных тегов или перенаправлений. Руководство различает загрузки, управляемые потоком, удерживаемые handles и документы плейлистов, созданные парсером.

<!-- section:7 -->
## Документация и проверка

Запускайте проверки в этом репозитории. Статические проверки не заменяют сборку Swift, раскрытие макросов, DocC и приёмочные тесты устройств или сервисов. Уберите INNONETWORK_LOCAL_PATH из окружения для проверки опубликованного графа зависимостей.

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
