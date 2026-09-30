# Failure and incident contracts (Draft)

`HLSFailureReport.classify` produces a category, backend, optional operation ID,
existing HLS NSError code and conservative recovery advice. Underlying errors,
descriptions and arbitrary domains are not copied. Parse `inspect` returns a
structured result; the existing throwing parser remains available. Neither
path claims line-level information the parser does not produce.

Recovery advice never executes work. Transient status/URL errors remain subject
to caller request policy. Authorization failures require application action.
Wrapping a known URL cause, including typed InnoNetwork transport wrappers,
preserves its cancellation/non-transient classification. Invalid URL and
untrusted-certificate URL errors do not acquire retry, checkpoint or native
restoration advice just because they are wrapped. Core trust failures require
security handling without retry advice; invalid core admission/configuration
requires reconfiguration. Unknown error chains are not recursively unwrapped.
Checkpoint recovery covers automatic VOD/single-file and offline-package
resource plans, plus opt-in DVR recovery. It still requires an enabled policy
and a matching durable checkpoint; the capability is not a guarantee that a
checkpoint exists. Native restoration uses system task IDs/session restoration, not
foreground checkpoint ownership. Capabilities describe backend lifetime and
recovery only; parsing a feature does not authorize executing it.

VOD, Live watch and DVR handles expose terminal `failureReport` without changing
their authoritative results. Native and audio APIs retain their existing
typed failures. Configuration helpers classify invalid dynamic settings.

`byteRangePlaylistUnsupported` is a retained legacy classification, not a
current downloader emission. Its NSError code remains reserved. No existing
error code or persisted media/checkpoint schema is renumbered.

`HLSIncidentBuffer` is explicit, application-side and bounded to 1...128 scalar
records. It does not intercept requests or collect raw operation events. Records
accept only typed stages and reports: no URL/path/header/body/key fields, no
free-form text or arbitrary NSError domain. Correlation is a random operation
UUID; mismatched report IDs are rejected. Snapshot drop count is exact for
this retained buffer, unlike observation's pre-enqueue drop metadata. Sequence
exhaustion is a typed failure. Do not invoke the actor from realtime callbacks.
