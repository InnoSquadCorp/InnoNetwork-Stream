# Parsing and downloading

`try HLSPlaylistParser(maximumPlaylistBytes: 2_097_152)` creates a bounded,
effect-free parser. `try parser.parse(text, relativeTo: sourceURL)` returns
`HLSPlaylistDocument`: switch `.media(let media)` / `.multivariant(let master)`.
Media exposes `segmentCount`, `hasEndList`, `targetDuration`, sequences and
metadata. Multivariant exposes variants/renditions. Do not call the internal
`HLSPlaylist(...)` initializer or assume every parsed document has media.
`document.legacyPlaylist` is lossless interoperability. `inspect` returns
`Result<HLSPlaylistDocument,HLSFailureReport>`, not invented line diagnostics.

Parsing resolves relative references but fetches no resources. Imported DEFINE
values are caller-provided. `media.validateSingleFileDownload()` checks backend
admission; parse success alone does not prove media, encryption, entitlement or
storage support. `PlaylistResolver.load(from:)` performs typed network loading;
a retained preparation is an advisory preview, not authorization to execute it.

## Single-file VOD

```swift
import Foundation
import InnoNetworkHLS

@HLSDownloadDefinition(maximumMediaResourceBytes: 8_388_608,
                       maximumTotalDownloadBytes: 268_435_456,
                       maximumConcurrentResourceTransfers: 3)
enum MovieDownload {}

func saveMovie(source: URL, destination: URL, session: URLSession) async throws -> HLSDownloadReceipt {
    let operation = try MovieDownload.start(sourceURL: source, destinationURL: destination, session: session)
    return try await withTaskCancellationHandler {
        try await operation.receipt()
    } onCancel: {
        operation.cancel()
    }
}
```

`configuration()` and `makeDownloader(...)` perform no requests. `prepare(...)`
loads the bounded playlist selection without media writes; `start` resolves
again. `HLSDownloadTask.events()` is throwing and returns a nonthrowing
`AsyncStream<HLSDownloadObservation>`. It admits at most 64 independent
subscriptions, newest-16 buffering, with operation ID/sequence/drop metadata.
Use `for await`, then `receipt()` for terminal success/failure. Slow or cancelled
observers do not own the transfer. Retain the handle; explicit cancellation or
owner release ends unfinished work. Do not delete a committed file on late cancel.

## Atomic offline presentation

```swift
@HLSOfflinePackageDefinition(maximumMediaResourceBytes: 8_388_608,
                             maximumTotalDownloadBytes: 268_435_456,
                             maximumConcurrentResourceTransfers: 3)
enum OfflineMovie {}
```

`try await OfflineMovie.downloadPackage(sourceURL:destinationDirectoryURL:session:)`
is task-owned. It preserves selected audio/subtitle timelines and returns an
`HLSOfflinePackageReceipt` after atomic publication, never overwriting an
existing destination. Default recovery preserves resumable checkpoints rather
than exposing an incomplete destination. Reopen using
`try HLSOfflinePackageStore().open(at: receipt.directoryURL)`.

For independent progress, retain `try OfflineMovie.start(...)` instead.
`try operation.events()` returns an **AsyncThrowingStream**, consumed with
`for try await`; its cancellation does not cancel the producer. The operation
uses explicit `cancel()` and authoritative `try await receipt()`. Do not transfer
the legacy downloader's observation-owned cancellation contract to these handles.

Dynamic equivalent: conform to `HLSDownloadDefining` or
`HLSOfflinePackageDefining`, implement `static func configuration() throws`
returning `.validated(...)`. Concurrency must be `1...8`; resource limits must
fit supported 32-bit Int and not exceed the Int64 total budget. Validation throws,
whereas legacy `advanced(...)` may clamp. Prefer static macro literals only when
settings are known at compilation. Never fabricate mutable configuration setters.

Pass `session`, `requestContext`, `requestPolicy` to definition entry points.
Policy may adapt headers/URL but must retain GET and no body. Keep cancellation,
trust, byte-range checks and bounded retry behavior; resume requires a matching
checkpoint and enabled policy. Single-file and offline backends have distinct
capabilities; use admission results instead of concatenating arbitrary HLS media.
