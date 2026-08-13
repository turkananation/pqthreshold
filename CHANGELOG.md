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
