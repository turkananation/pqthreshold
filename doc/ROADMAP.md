# ROADMAP.md

**pqthreshold** — Implementation phases toward v1.0

Status: planning  
**Implementer entrypoint:** [INDEX.md](INDEX.md)  
Prerequisites: all docs listed in INDEX §2

---

## Phase 0 — Specification

- [x] Architecture, security, ceremonies, integration docs
- [x] Scheme lock: FROST Ed25519 + Feldman VSS + Gennaro DKG
- [x] Serialization spec and ADRs
- [x] API contract (Tier 1 / Tier 2)
- [x] Dependency policy: `pqforge` + `swissarmyknife`
- [x] [INDEX.md](INDEX.md) — reading order and phase map
- [x] [PARAMS.md](PARAMS.md) — t/n/index limits
- [x] [FROST_PROFILE.md](FROST_PROFILE.md) — ciphersuite pin
- [x] [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) — wire formats
- [x] [TEST_VECTORS.md](TEST_VECTORS.md) — vector layout
- [x] [SECURITY.md](SECURITY.md) Appendix A
- [x] [IMPLEMENTATION.md](IMPLEMENTATION.md) — module build order
- [x] [TOOLING.md](TOOLING.md) — verify + CI
- [x] [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) — v1.0 gate
- [x] CI workflow (`.github/workflows/ci.yml`)
- [x] `tool/verify.dart` release gate
- [x] `test/vectors/` layout + README

**Phase 0 complete.** Begin Phase 1 per [IMPLEMENTATION.md](IMPLEMENTATION.md) §4.

## Phase 1 — Foundation

Docs: [PARAMS.md](PARAMS.md), [SERIALIZATION.md](SERIALIZATION.md) §3–4.1, [API.md](API.md) §3.1–3.2, [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.1–3.4

- [x] `lib/src/params/` — `ThresholdParams`, `SchemeId`; validate with swissarmyknife `Validator`
- [x] `lib/src/errors/` — sealed `ThresholdException`; map internal `Result` failures at barrel
- [x] `lib/src/util/` — `Disposable` secret buffers; byte helpers from swissarmyknife where non-crypto
- [x] `lib/src/serialization/` — `CodecPipeline` encode/decode for `PQTH` format
- [x] Unit tests for params validation and serialization round-trips
- [x] `bin/pqthreshold.dart` — Phase 1 CLI (`params`, `inspect`); see [TERMINAL.md](TERMINAL.md)

**Phase 1 complete.** Begin Phase 2 per [IMPLEMENTATION.md](IMPLEMENTATION.md) §5.

## Phase 2 — Verifiable secret sharing

Docs: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §4, [FROST_PROFILE.md](FROST_PROFILE.md) §6, [TEST_VECTORS.md](TEST_VECTORS.md) §4.1

- [x] `lib/src/sharing/` — Feldman VSS split / verify / reconstruct
- [x] `lib/src/scheme/feldman/` — Ed25519 group math (vendored field ops; pqforge has no group API)
- [x] Property tests: `t-1` fails, `t` succeeds
- [x] Vectors under `test/vectors/feldman/`

**Phase 2 complete.** Begin Phase 3 per [IMPLEMENTATION.md](IMPLEMENTATION.md) §6.

## Phase 3 — Distributed key generation

Docs: [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3, [CEREMONIES.md](CEREMONIES.md) C1, [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.5

- [x] `lib/src/dkg/` — `CeremonySession` backed by swissarmyknife `StateMachine`
- [x] `lib/src/transcript/` — hash chain
- [x] In-process `DkgSimulator` (Tier 2) in `lib/testing.dart`
- [x] Integration test: simulated C1 for 2-of-3 and 3-of-5
- [x] Vectors under `test/vectors/dkg/`

**Phase 3 complete.** Begin Phase 4 per [IMPLEMENTATION.md](IMPLEMENTATION.md) §7.

## Phase 4 — Threshold signing

Docs: [FROST_PROFILE.md](FROST_PROFILE.md), [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §5, [TEST_VECTORS.md](TEST_VECTORS.md) §4.3

- [ ] `lib/src/signing/` — FROST partial sign, combine, verify
- [ ] `lib/src/scheme/frost/` — protocol math
- [ ] Combined signature verifies via `PqClassical.provider.ed25519Verify`
- [ ] Vectors under `test/vectors/frost/`

## Phase 5 — Ceremony helpers

Docs: [CEREMONIES.md](CEREMONIES.md), [API.md](API.md) §4.4, [SERIALIZATION.md](SERIALIZATION.md) §4.6

- [ ] `lib/src/ceremony/` — `RootCeremony`, signing orchestration, rotation
- [ ] `ContinuityProof` encode/decode
- [ ] Example app using Tier 2 simulation

## Phase 6 — v1.0 readiness

- [ ] All [TEST_VECTORS.md](TEST_VECTORS.md) acceptance criteria pass
- [ ] Independent review checklist
- [ ] CHANGELOG 1.0.0 when Tier 1 API is stable

## v2 (deferred)

- C6 proactive share refresh
- C4-B re-share without full reconstruct
- Pedersen VSS
- Post-quantum threshold schemes (when standards mature)
