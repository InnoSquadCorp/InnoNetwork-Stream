# Macro-first migration (unreleased 1.0 Draft)

There is no published Stream 1.0 API to rewrite. These breaking migrations apply
to local/pre-release adopters; InnoNetwork 6.0.0 and media/checkpoint schemas do
not change. No application source migration is performed by this repository.

| Previous path | Primary path | Ownership and failure contract |
| --- | --- | --- |
| Public `HLSPlaylist(...)` construction | `HLSPlaylistParser().parse(_:relativeTo:)` | Parser-produced discriminated media/multivariant metadata; malformed input throws |
| `PlaylistResolver.resolve(from:)` flat value | `PlaylistResolver.load(from:)` typed document | Same bounded caller-owned transport and admission |
| Optional kind-field interpretation | Switch `HLSPlaylistDocument`, then typed selector overloads | No contradictory public construction; `legacyPlaylist` is lossless interoperability |
| Manual VOD configuration boilerplate | `@HLSDownloadDefinition` | Compile-time constant checks; `validated(...)` is the dynamic/recovery equivalent |
| Stream-owned foreground download | Definition `start` + retained `HLSDownloadTask` | Cancelling an observer only cancels observation; explicit `cancel()` or owner release stops work |
| Downloading from retained preparation | Definition `prepare`, then fresh `start` | Preview is advisory; execution resolves identity/admission again |

Authoring input remains text at the pure parser boundary. We do not add a second
partially validated Swift authoring builder duplicating HLS syntax checks.
Existing parsed metadata and advanced flat selector overloads remain available;
the flat constructor is now internal for legacy regression fixtures only.

Compile macro-first and manual equivalents externally in both Debug and
Release. A parser-success value is not entitlement, DRM support, disk capacity,
or executable-backend capability proof.
