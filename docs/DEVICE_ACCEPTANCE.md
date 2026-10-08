# Application-owned device acceptance for Stream 6.1.1

Status: PREPARED, NOT EXECUTED. SDK tests and platform builds are not device,
entitlement, credential, DRM-provider, locked-storage, or power-loss evidence.
No Mac/device work, login, signing change, or provisioning update is authorized
by the existence of this checklist.

Record candidate commit, Core lock revision, app build, device/OS, network, steps,
observed outcomes, and a redacted evidence location. Do not store Apple sessions,
SPC/CKC, keys, private playback URLs, user tokens, or entitlement secrets in this
repository. A skipped scenario must remain explicitly unverified.

## Background restoration (when used)

- Start a native asset download and record the system task identifier.
- Background the app, allow system suspension, then reopen/relaunch it through
  supported OS delivery paths. Do not assume a force-quit allows automatic resume.
- Reconnect the same session identifier using the completion-accepting initializer
  synchronously in the application delegate callback, before returning.
- Confirm delivery on main, one completion per native batch/invalidation, no
  replay to a later registration, and no duplicate native download.
- Cancel only an event observer: the download must continue. Explicitly cancel
  the native task: its cancellation must become observable.

## Device lock and protected storage (when used)

- Repeat download/DVR checkpoint and offline-open operations while locking and
  unlocking a physical device with the app's actual protection configuration.
- Verify unavailable storage causes a bounded observable error; never publish a
  success receipt for missing/corrupt media. Unlock and retry/recover normally.
- Reopen the latest acknowledged checkpoint, verify retained media and hashes,
  and check the application's chosen retention/cleanup policy.
- Fault-injection tests cover software-visible failures, not battery removal or
  physical disk/controller loss. State any destructive test limits separately.

## FairPlay provider acceptance (when used)

The app owns entitlement/signing, certificate retrieval, KSM authorization and
persistent-key storage. Use an authorized test asset/provider account and review
its data destinations before running. Existing `Scripts/run_fairplay_acceptance.sh`
requires a physical iOS destination and explicit application configuration.
Provisioning updates remain opt-in via its documented flag.

Verify initial SPC v3 license acquisition, renewal, cancellation at network and
persistence boundaries, offline asset reopening with persisted keys, and the
expired/revoked-key error path. Check that logs redact URLs, credentials and
DRM payloads. A clear-content Apple conformance report cannot certify DRM.

## Release decision

The maintainer records PASS / FAIL / NOT RUN for each applicable scenario and
states the intended feature scope. An unused integration can be explicitly
outside an application's deployment; it must not be advertised as validated.
