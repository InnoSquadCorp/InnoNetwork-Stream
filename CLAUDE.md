# InnoStream repository instructions

- Support Apple platforms only and use Swift 6 language mode with strict
  concurrency.
- Keep bounded playlist, key, and media-resource reads; never replace them with
  unbounded buffering.
- Preserve the public module names during the InnoNetwork 6 package split.
- Use Swift Testing for unit and integration tests.
- Treat FairPlay tests as opt-in acceptance tests requiring caller-provided
  credentials and entitlement context.
- Do not weaken URL admission, redirect, trust, retry-idempotency, or
  cancellation behavior inherited from InnoNetwork.
