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
