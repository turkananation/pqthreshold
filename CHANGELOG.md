# Changelog

## 1.1.0

### Added

- **`ShareMetadata`** and **`ShareMetadata.fromBytes`** — read a serialized
  share's `threshold` (`t`), `totalParticipants` (`n`), `index`,
  `participantId`, `ceremonyId`, `scheme` and `formatVersion` **without
  materializing the secret scalar**.
  - Previously the only way to read those fields was `Share.fromBytes`, which
    fully decodes the 32-byte scalar into a live `SecretBuffer`. A third-party
    key store holding shares as opaque sealed bytes could therefore not describe
    or validate what it held without first exposing what it held — which
    inverts the custody model `doc/TERMINAL.md` requires ("unwrap only in
    process").
  - The decoder stops at the end of the metadata prefix. The secret share and
    the verification blob are never read, so the scalar never exists in the
    reading process.
  - **Reading metadata is not authentication.** It reports what the bytes claim
    to be. A caller needing authenticity must unwrap and use
    `VerifiableSecretSharing.verifyShare`. This type is for describing and
    indexing shares, never for trusting them.
- **`validateShareIndex(index, params)`** and **`validateParticipantId(id)`**
  are now public, along with `maxParticipantIdCodeUnits`. Both checks previously
  lived only inside `@internal Share.create`, so a caller could not validate a
  participant index or label without constructing a `Share` — which requires the
  secret.
- **`Share.disposeSecret()`** is public. A custodian that unwraps a share to
  hand it to a signing ceremony had no reachable way to wipe it. Metadata
  (`params`, `ceremonyId`, `participantId`, `index`, `verificationData`) remains
  readable afterwards; operations needing the scalar throw `StateError`.

### Changed

- **`SecretBuffer.use(fn)`** and **`SecretBuffer.mutate(fn)`** — read-only and
  read/write windows onto the managed buffer, mirroring
  `package:zeroize`'s `SecretBytes`.
  - `SecretBuffer.bytes` returns a plain copy that nothing owns or wipes — the
    exact pattern that makes a buffer survive in the heap until collection. It
    remains for APIs that require a bare `Uint8List`, and its documentation now
    says to wipe it.
  - `use`/`mutate` hand out the managed backing store, so `dispose()` wipes
    exactly what the caller was given.

No wire-format change. `ShareMetadata` parses the existing PQTH layout and
`Share.toBytes()` output is byte-identical. `t`/`n` are still re-validated on
the wire path by `ThresholdParams.fromBytes`.

### Fixed

- **The `quick` release gate no longer fails on `packages/crypto_shared`.** The
  root `dart analyze` walks the whole repository, but a nested package has no
  entry in the root `package_config.json`, so every
  `package:crypto_shared/...` import failed to resolve and CI went red on the
  root package's own gate. `packages/**` is now excluded from the root
  `analysis_options.yaml`, and `tool/verify.dart quick` resolves, analyses and
  tests each nested package in its own directory. The nested package is
  **covered by the gate, not skipped by it** — coverage is now stronger than
  before, because crypto_shared is also analyzed rather than only tested.
- Corrected the stale claim that `crypto_shared` is unpublished. It is published
  as `package:crypto_shared` 1.0.0. See `README.md`.

## 1.0.1

- Exclude the separately published `crypto_shared` companion package from the
  `pqthreshold` pub.dev archive. (`crypto_shared` is published on its own as
  `package:crypto_shared` 1.0.0; earlier notes in this file described it as
  unpublished, which was incorrect.)
- Move ML-DSA and Mithril APIs behind explicit experimental library barrels.
- Document the stable FROST-only API boundary and companion package location.

## Unreleased (v2)

### Operator CLI

- [x] **`dkg participant step`** — multi-round C1 over `--ceremony-dir` with `transport/` inbox/outbox.
- [x] **`sign partial` → `sign round2` → `sign combine`** — disk round-trip for distributed FROST (binding-factor round).
- [x] **`sign ml-dsa run|verify`** — ML-DSA-44 threshold sign + optional `--wire-dir` export (M3 beta).
- [x] **`sign ml-dsa partial|round2|round3|combine`** — per-officer distributed ML-DSA wire rounds (M3+).

### Tier 1 API

- [x] **`FrostSigningMessage`** wire codec (`doc/PROTOCOL_MESSAGES.md` §5).
- [x] **`MlDsaSigningMessage`** wire codec (`doc/PROTOCOL_MESSAGES.md` §6).
- [x] **`MlDsaSigningSession`** — three-round ML-DSA with officer-local checkpoint.
- [x] **`SigningSession`** — two-round FROST with officer-local checkpoint.
- [x] **`CeremonySession.exportCheckpoint` / `fromCheckpoint`** — DKG dir-transport persistence.

### Ceremonies (planned)

- [ ] **C6** proactive share refresh.
- [ ] **C4-B** re-share without full reconstruct.

### Cryptography (v2 PQ — M2 beta)

- [x] **ADR-004** + profiles + `SchemeId` registry (M1)
- [x] **`MlDsaShare` / `MlDsaPublicKey`** PQTH kinds `0x07`–`0x09`
- [x] **`MlDsaThresholdSigner`** + `MlDsaRootCeremony` / `MlDsaThresholdSigningCeremony` (Tier 2 simulate)
- [x] **`tool/mithril_bridge`** — Mithril ML-DSA-44 threshold via [threshold-ml-dsa](https://github.com/lattice-safe/threshold-ml-dsa)
- [x] **`MlDsaSigningMessage`** wire codec + **`signWithWire`** / `sign ml-dsa run` (M3 beta — Mithril coordinator exports rounds)
- [x] **`MlDsaSigningSession`** + distributed CLI (M3+ — deterministic party RNG, officer checkpoints)
- [ ] Per-party RSS export without shared ceremony seed (production DKG)
- [ ] Pure Dart ML-DSA-65 lattice MPC (M4)
- [ ] **Pedersen VSS** (new verification mode).

### Integration (planned)

- [ ] Wrapped share CLI (`*.share.wrapped.json`) aligned with pqforge custody.
- [ ] Persistent Serverpod relay (beyond in-memory sketch).

## 1.0.0

**Stable Tier 1 release** — `frostEd25519V1` only; PQTH `ver=0x01` frozen per [doc/API.md](doc/API.md) §7.

### Operator CLI (0.7.0 scope)

- **`vss split|verify|reconstruct`** — C2 dealer ceremony on terminal.
- **`dkg simulate`** — in-process C1 DKG with PQTH artifact export (CI/operator).
- **`sign run|partial|combine|verify`** — C3 threshold signing; `sign run` is the primary path from share files.
- **`ceremony run --flow c1|c3|c5|full`** — orchestrated in-process ceremony workflows.
- Tier 1 **`DealerCeremony`** (C2) and **`RecoveryCeremony`** (C4) helpers.

### Distributed integration (0.8.0 scope)

- **`packages/crypto_shared`** — relay, `OfficerDkgClient`, `DistributedDkgCoordinator`, `OfficerSigningClient`, `DistributedSigningCoordinator`, share wrap/unwrap aligned with pqforge `PqWrappedKey`.
- **`example/serverpod_integration/`** — Serverpod endpoint sketch with `ThresholdCeremonyService`.
- **`PublicKey.fromShareSet()`** — public API for joint key derivation from shares.
- Relay-based C3 tests without `SigningSimulator`; `crypto_shared` tests in `tool/verify.dart full`.

### Pre-1.0 hardening (0.9.0 scope)

- **77 tests** in main package + **6** in `crypto_shared`; `dart run tool/verify.dart full` passes.
- [REVIEW_CHECKLIST.md](doc/REVIEW_CHECKLIST.md) published — independent cryptographic sign-off recommended before high-assurance deployment.

Requires **pqforge ^0.4.4**.

## 0.6.0

- **Feldman VSS** — split, verify, reconstruct (C2 dealer-based sharing).
- **Gennaro DKG** — `CeremonySession`, transcripts, wire messages (C1).
- **FROST threshold signing** — Ed25519-compatible aggregate signatures (C3).
- **Ceremony helpers** — `RootCeremony`, `RotationCeremony`, `ContinuityProof` (C5).
- Tier 2 simulators in `package:pqthreshold/testing.dart`.
- Acceptance vectors under `test/vectors/`; `dart run tool/verify.dart full` passes.
- Requires **pqforge ^0.4.4** (`PqBytes.sha512` for FROST profile hashes).
- Independent cryptographic review checklist: `doc/REVIEW_CHECKLIST.md` (recommended before production).
- **Phase 5 ceremony helpers:** C1/C3/C5 orchestration per `doc/API.md` §4.4.
- `RootCeremony.startSession` / `simulate`, `ThresholdSigningCeremony.simulate`, `RotationCeremony.simulate`.
- `ContinuityProof` type with PQTH wire codec (`doc/SERIALIZATION.md` §4.6).
- Example app runs C1 → C3 → C5 via Tier 2 simulators.
- FROST SHA-512 via `PqBytes.sha512` from pqforge 0.4.4 (no direct `crypto` dependency).
- Six ceremony tests in `test/ceremony/ceremony_test.dart`; `dart run tool/verify.dart full` passes.

## 0.5.0

- **Phase 4 FROST threshold signing:** Ed25519-compatible aggregate signatures (C3).
- `ThresholdSigner.signPartial`, `combine`, `verify` per `doc/API.md` §4.3.
- `PartialSignature` type with PQTH wire codec (`doc/SERIALIZATION.md` §4.4).
- FROST core under `lib/src/scheme/frost/` (binding factors, group commitment, Lagrange shares).
- Challenge hash uses RFC 8032 FROST-Ed25519 H2 so `PqClassical.provider.ed25519Verify` succeeds.
- FROST acceptance vector in `test/vectors/frost/`; `tool/generate_frost_vectors.dart` for regeneration.
- Five signing tests in `test/signing/frost_test.dart`; `dart run tool/verify.dart full` passes.

## 0.4.0

- **Phase 3 distributed key generation:** Gennaro DKG over Ed25519 (C1).
- `CeremonySession` with swissarmyknife `StateMachine` per `doc/PROTOCOL_MESSAGES.md` §3.1.
- DKG wire messages (`DkgMessage`) for Round1/Round2 packages.
- `Transcript` hash-chain append, seal, verify, and PQTH wire codec.
- Tier 2 `DkgSimulator` in `package:pqthreshold/testing.dart`.
- DKG acceptance vectors in `test/vectors/dkg/`; `tool/generate_dkg_vectors.dart` for regeneration.
- Five integration tests in `test/dkg/dkg_simulation_test.dart`; `dart run tool/verify.dart full` passes.

## 0.3.0

- **Phase 2 verifiable secret sharing:** Feldman VSS over Ed25519.
- `VerifiableSecretSharing.split`, `verifyShare`, `reconstruct` per `doc/API.md` §4.2.
- `Share` and `PublicKey` types with PQTH wire codecs (`doc/SERIALIZATION.md` §4.2–4.3).
- In-tree Ed25519 curve/field ops under `lib/src/scheme/feldman/` (pqforge has no group API).
- Feldman acceptance vectors in `test/vectors/feldman/`; `tool/generate_feldman_vectors.dart` for regeneration.
- Six unit tests in `test/sharing/feldman_test.dart`; `dart run tool/verify.dart full` passes.

## 0.2.0

- **Phase 1 foundation:** params, errors, PQTH serialization, and util modules.
- `ThresholdParams` / `SchemeId` with swissarmyknife `Validator` and canonical 16-byte wire format.
- Sealed `ThresholdException` hierarchy; internal `Result` bridged at public API boundary.
- `PqthHeader`, `ThresholdParamsCodec`, `BinaryReader`/`BinaryWriter` per `doc/SERIALIZATION.md`.
- `SecretBuffer` (Disposable wipe), `validateCeremonyId` / `generateCeremonyId`.
- Phase 1 CLI (`pqthreshold params`, `pqthreshold inspect`) per `doc/TERMINAL.md`.
- 32+ unit tests across params, serialization, util, CLI, and package smoke; `dart run tool/verify.dart full` passes.

## 0.1.0

- Planning release: formative architecture, security, ceremony, and integration docs.
- Locked v1 scheme stack (FROST Ed25519, Feldman VSS, Gennaro DKG) in `doc/SCHEMES.md`.
- Added implementer index (`doc/INDEX.md`), protocol specs, params, test vector plan, implementation guide, tooling, release checklist.
- CI (`.github/workflows/ci.yml`) and `tool/verify.dart` release gate.
- ADRs for scheme selection, runtime dependencies, and serialization format.
- Implementation scaffold only; no cryptographic functionality yet.
