# InnoNetwork-Stream

[English](README.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Deutsch](README.de.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [Русский](README.ru.md)

[6.1.1](https://github.com/InnoSquadCorp/InnoNetwork-Stream/releases/tag/6.1.1)

<!-- section:1 -->
## Alcance

Análisis HLS, descargas VOD/offline acotadas, directo/DVR, integración nativa de reproducción/FairPlay y audio decodificado. No es una interfaz de reproductor, CDN, transcodificador ni servicio DRM. Elige InnoNetwork-Stream o los productos individuales InnoNetworkHLS, InnoNetworkHLSLive, InnoNetworkHLSAVFoundation e InnoNetworkHLSAudio. Estos cuatro nombres son módulos Swift; no existe InnoNetworkStream.

Las siete guías rápidas cubren la misma versión estable, instalación, ejemplo, ciclo de vida y migración. La guía detallada en inglés es la referencia avanzada común; las traducciones no implican revisión por hablantes nativos.

<!-- section:2 -->
## Requisitos

Swift 6.2 o posterior, modo de lenguaje Swift 6. Solo Apple: iOS 16+, macOS 14+, tvOS 16+, watchOS 9+, visionOS 1+. Core está fijado exactamente a InnoNetwork 6.1.1.

El audio decodificado requiere además Swift 6.4/Xcode 27 y APIs compatibles de OS 27; comprueba la disponibilidad de cada símbolo. La superficie Swift 6.2 es distinta. Las seis macros usan fábricas validated que pueden lanzar errores. configuration() no inicia tráfico de red.

<!-- section:3 -->
## Instalación

Añade estas dependencias y después los productos al target consumidor.

```swift
.package(url: "https://github.com/InnoSquadCorp/InnoNetwork-Stream.git", from: "6.1.1"),
```

```swift
.product(name: "InnoNetwork-Stream", package: "InnoNetwork-Stream"),
```

<!-- section:4 -->
## Inicio rápido

Los ejemplos se han contrastado con el código fuente; no representan una nueva compilación ni prueba en dispositivos. La aplicación gestiona URLs, credenciales y políticas de transporte.

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
## Propiedad y errores

Conserva el handle. Cancelar observadores o esperas de receipt no detiene el productor; llama a cancel() o propaga la cancelación como en el ejemplo. receipt() es el resultado definitivo; events() permite hasta 64 suscripciones con los 16 eventos más recientes y metadatos de secuencia/pérdida. Una cancelación tardía no elimina la salida terminada. Captura los errores y consulta los contratos tipados de fallos; evita registrar URLs, credenciales o medios.

La función asíncrona offline downloadPackage ejecuta el trabajo en la tarea llamadora y hereda su cancelación; los handles start separan observación y cancelación. Las tareas nativas de fondo conservan la restauración del sistema. Credenciales, permisos y claves FairPlay pertenecen a la aplicación; publicar la biblioteca no certifica servicios ni dispositivos.

<!-- section:6 -->
## Migración

Desde los antiguos productos HLS de Core añade esta dependencia y conserva los imports individuales. Desde el checkout InnoStream no publicado, cambia URL, identidad y argumentos package: del producto. No supongas etiquetas antiguas ni redirecciones. La guía distingue descargas controladas por streams de handles retenidos y documentos producidos por el parser.

<!-- section:7 -->
## Documentación y validación

Ejecuta estas comprobaciones desde este repositorio. Las pruebas estáticas no sustituyen compilación Swift, expansión de macros, DocC ni aceptación en dispositivos o servicios. Elimina INNONETWORK_LOCAL_PATH del entorno para validar el grafo publicado.

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
