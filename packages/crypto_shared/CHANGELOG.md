# Changelog

## 1.0.1

Dependency floors only. No API change and no behavioural change in this package.

- `pqforge` `^0.4.5` → `^0.4.7`. Argon2id cost parameters are range-checked before
  the KDF runs, so a stored record can no longer request an arbitrary allocation
  before authentication; and every secret-buffer wipe in pqforge's `lib/` now
  routes through `package:zeroize`'s `secureZero` rather than a `fillRange` the
  AOT compiler could elide.
- `pqthreshold` `^1.0.1` → `^1.1.0`. `ShareMetadata.fromBytes` parses a share's
  participant index and ceremony id without materialising the secret, and
  `validateShareIndex` / `validateParticipantId` are now public, so a coordinator
  holding an untrusted share can reject a malformed header in its own typed error
  before anything parses the body.
- Description expanded to name verifiable secret sharing explicitly.

## 1.0.0

- Initial public release of shared pqthreshold and pqforge integration helpers.
- Added DKG relay and officer client abstractions.
- Added distributed DKG and signing coordinators.
- Added `ThresholdCeremonyService`, signing jobs, hex codecs, and share wrapping helpers.

This package provides coordination helpers only. Authentication, authorization, persistence, and network transport remain application responsibilities.
