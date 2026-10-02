# Macro-first migration (unreleased 1.0 Draft)

## Live, DVR and native playback

Prefer `@HLSLiveDefinition` and `@HLSDVRDefinition` for bounded static settings;
their `configuration()` uses the same throwing `validated()` factory as dynamic
callers. Legacy `advanced()` packs explicitly normalize values and remain for
key preload, steering, rolling retention and recovery tuning.
`HLSLiveDefining.watch` returns an explicitly retained foreground owner. Zero,
slow or multiple observers do not own reloads. ENDLIST produces an awaitable
`finalSnapshot`; cancel the handle to stop reloads. DVR's first stop/commit or
discard intent still wins. `receipt()` and `observations()` issue no lifecycle
commands; the legacy `events` property remains single-channel.

`@HLSPlaybackDefinition` applies settings to a caller-owned item on MainActor;
it never creates/plays a player. Native background downloads retain system task
IDs and session restoration semantics. Cancelling an event observer does not
cancel a native download. Realtime audio keeps its native callback boundary,
not an actor hop or generated foreground lifetime.

## Parser and VOD migration

There is no published Stream 1.0 API to rewrite. These breaking migrations apply
to local/pre-release adopters; InnoNetwork 6.0.0 and media/checkpoint schemas do
not change. No application source migration is performed by this repository.

| Previous path | Primary path | Ownership and failure contract |
| --- | --- | --- |
| Public `HLSPlaylist(...)` construction | `HLSPlaylistParser().parse(_:relativeTo:)` | Parser-produced discriminated media/multivariant metadata; malformed input throws |
| `PlaylistResolver.resolve(from:)` flat value | `PlaylistResolver.load(from:)` typed document | Same bounded caller-owned transport and admission |
| Optional kind-field interpretation | Switch `HLSPlaylistDocument`, then typed selector overloads | No contradictory public construction; `legacyPlaylist` is lossless interoperability |
| Manual VOD configuration boilerplate | `@HLSDownloadDefinition` | Compile-time constant checks; `validated(...)` is the dynamic/recovery equivalent |
| Manual offline package configuration | `@HLSOfflinePackageDefinition` | Same atomic multi-rendition engine; `downloadPackage` runs in the calling task and inherits its cancellation |
| Stream-owned foreground download | Definition `start` + retained `HLSDownloadTask` | Cancelling an observer only cancels observation; explicit `cancel()` or owner release stops work |
| Downloading from retained preparation | Definition `prepare`, then fresh `start` | Preview is advisory; execution resolves identity/admission again |

Authoring input remains text at the pure parser boundary. We do not add a second
partially validated Swift authoring builder duplicating HLS syntax checks.
Existing parsed metadata and advanced flat selector overloads remain available;
the flat constructor is now internal for legacy regression fixtures only.

Compile macro-first and manual equivalents externally in both Debug and
Release. A parser-success value is not entitlement, DRM support, disk capacity,
or executable-backend capability proof.

## Production boundary tightening

All HLS request adapters must preserve a bodyless GET. URLs, credentials and
headers may be adapted, but method/body replacement is rejected before Core
transport because resource retries assume GET semantics. Cancellation is checked
on both sides of asynchronous adaptation. Empty media resources or decrypted
plaintext fail instead of publishing incomplete presentations. VOD and DVR range
responses require valid Content-Range syntax and consistent received byte counts,
including open-ended responses without Content-Length. Existing healthy streams,
media/checkpoint schemas, Core trust policy and ownership boundaries are unchanged.
