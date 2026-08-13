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

- [x] `lib/src/signing/` — FROST partial sign, combine, verify
- [x] `lib/src/scheme/frost/` — protocol math (H1/H3/H4/H5 + Ed25519 challenge)
- [x] Combined signature verifies via `PqClassical.provider.ed25519Verify`
- [x] Vectors under `test/vectors/frost/`

**Phase 4 complete.** Phase 5 complete — begin Phase 6 per [IMPLEMENTATION.md](IMPLEMENTATION.md) §9.

## Phase 5 — Ceremony helpers

Docs: [CEREMONIES.md](CEREMONIES.md), [API.md](API.md) §4.4, [SERIALIZATION.md](SERIALIZATION.md) §4.6

- [x] `lib/src/ceremony/` — `RootCeremony`, signing orchestration, rotation
- [x] `ContinuityProof` encode/decode
- [x] Example app using Tier 2 simulation

## Phase 6 — v1.0 readiness

- [x] All [TEST_VECTORS.md](TEST_VECTORS.md) acceptance criteria pass
- [x] Independent review checklist ([REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md))
- [x] CHANGELOG 1.0.0 when Tier 1 API is stable

**Phase 6 implementation gates done.** Tag `1.0.0` only after independent review sign-off on [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md).

---

## Signature coverage — what “v1” means

This is the most common source of confusion. **Two planes** exist in the stack ([INTEGRATION.md](INTEGRATION.md) §3, [TERMINAL.md](TERMINAL.md) §3):

| Plane | Owner | Signatures | pqthreshold v1 |
| ----- | ----- | ---------- | ---------------- |
| **A — Organizational root** | `pqthreshold` | FROST threshold → **64-byte Ed25519** | ✅ **One scheme:** `frostEd25519V1` |
| **B — Member device keys** | `pqforge` / `pqcrypto` | Hybrid **ML-DSA + Ed25519**, SLH-DSA, ML-KEM seal, … | ❌ **Not in this package** (by [ADR-001](adr/001-scheme-selection.md)) |

### Threshold signatures inside pqthreshold (Plane A)

| Use | Ceremony | Output | Status at 1.0.0 |
| --- | -------- | ------ | --------------- |
| Credential / policy / high-value sign | **C3** | Standard Ed25519 (64 bytes) | ✅ Library |
| Rotation continuity attestation | **C5** | Same Ed25519 under **old** joint key | ✅ Library |
| Dealer split attestation | **C2** | VSS commitments (not a standalone sig type) | ✅ `VerifiableSecretSharing` |
| Recovery reconstruct | **C4** | Secret export (high-privilege; not a sig) | ✅ `reconstruct` API only |

Both **C3** and **C5** use the **same** FROST ciphersuite — not separate signature algorithms.

### Explicitly **not** pqthreshold v1 (ADR-001, [SCHEMES.md](SCHEMES.md) §3.4)

| Capability | Target | Why deferred |
| ---------- | ------ | ------------ |
| ML-DSA / SLH-DSA **threshold** | **v2+** new `SchemeId` | Standards / implementations not stable enough for high-assurance v1 |
| ECDSA-P256 threshold | Out of scope | Different curve stack; pqforge primary path is Ed25519 |
| Hybrid threshold (classical + PQ in one combined sig) | **v2+** | Requires new profile + ADR |
| C6 share refresh, C4-B re-share, Pedersen VSS | **v2+** | Ceremony / VSS extensions |

**Full-stack “all signatures” for a Panthalassa-style app** = Plane A (pqthreshold) **+** Plane B (pqforge) at the **application** layer — not every algorithm inside `pqthreshold` itself.

---

## Release train: 0.6.0 → 1.0.0

Phases 0–6 delivered **core Tier 1 crypto** (C1–C5 library surface). Remaining work before **1.0.0** is operator tooling, distributed integration, and review — **not** new threshold signature schemes (those are v2 unless ADR-001 is amended).

| Version | Theme | Delivers | Docs |
| ------- | ----- | -------- | ---- |
| **0.6.0** | Core library | Phases 1–6: VSS, DKG, FROST, ceremonies, vectors, `params`/`inspect` CLI | [GETTING_STARTED.md](GETTING_STARTED.md) |
| **0.7.0** | Operator CLI | `vss`, `dkg simulate`, `sign`, `ceremony run`; C2/C4 Tier 1 helpers | [TERMINAL.md](TERMINAL.md) §4, §8 |
| **0.8.0** | Distributed production | `packages/crypto_shared`, signing relay, share wrap/unwrap, Serverpod sketch | [GETTING_STARTED.md](GETTING_STARTED.md) §14 |
| **0.9.0** | Pre-1.0 hardening | Review checklist published; verify gate + crypto_shared in CI | [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) |
| **1.0.0** *(current)* | Stable Tier 1 | API + PQTH `ver=0x01` freeze; **`frostEd25519V1` only** | [CHANGELOG.md](../CHANGELOG.md) |

**1.0.0 shipped.** Independent cryptographic review ([REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md)) remains recommended before high-assurance production. **v2** adds new threshold schemes (ML-DSA, etc.) per ADR-001.

---

## Phase 7 — Operator CLI (0.7.0) ✓

Docs: [TERMINAL.md](TERMINAL.md) §4, §8, [CEREMONIES.md](CEREMONIES.md) C2/C4

- [x] `pqthreshold vss split|verify|reconstruct` — C2 dealer ceremony on terminal
- [ ] `pqthreshold dkg participant` — C1 multi-party over `--transport dir` *(deferred v2; use `dkg simulate` + library `CeremonySession`)*
- [x] `pqthreshold sign run|partial|combine|verify` — C3 with pqforge-compatible Ed25519 verify exit code
- [x] `pqthreshold ceremony run --flow c1|c3|c5|full` — rotation + continuity proof export
- [x] C2 / C4 Tier 1 ceremony helpers (`DealerCeremony`, `RecoveryCeremony`)
- [x] CLI tests in `test/cli/`; [GETTING_STARTED.md](GETTING_STARTED.md) CLI table updated

## Phase 8 — Distributed integration (0.8.0) ✓

Docs: [INTEGRATION.md](INTEGRATION.md), [GETTING_STARTED.md](GETTING_STARTED.md) §13–14

- [x] Production-harden `packages/crypto_shared` (relay, signing jobs, hex codecs)
- [x] `OfficerSigningClient` + `DistributedSigningCoordinator` (mirror DKG client)
- [x] PQTH share bytes ↔ pqforge `PqWrappedKey` (`share_wrapping.dart`)
- [x] Serverpod example sketch (`example/serverpod_integration/`)
- [x] Integration tests: relay-based C3 round-trip without `SigningSimulator`

## Phase 9 — Pre-1.0 gate (0.9.0) ✓

- [x] [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md) published for independent review
- [ ] [SECURITY.md](SECURITY.md) Appendix A reviewer sign-off *(operator)*
- [ ] Sample git-history secret audit *(operator)*
- [x] `dart run tool/verify.dart full` + crypto_shared tests in CI

## Phase 10 — v1.0.0 tag ✓

- [x] [CHANGELOG.md](../CHANGELOG.md) — `## 1.0.0`
- [x] `pubspec.yaml` → `1.0.0`; [API.md](API.md) §7 stability note updated
- [x] Tier 1 surface frozen (additive changes only thereafter)

---

## v2 (in progress)

Requires new ADR(s) and new `SchemeId` values for PQ schemes — **not** a semver minor on v1.

### Shipped in Unreleased
- [x] `dkg participant step` — dir-transport C1 CLI
- [x] FROST two-round wire + `SigningSession` + `sign round2`
- [x] `CeremonySession` checkpoint for multi-step DKG

### Planned
- [ ] C6 proactive share refresh
- [ ] C4-B re-share without full reconstruct
- [ ] Pedersen VSS
- [ ] **Post-quantum threshold schemes** (ML-DSA, SLH-DSA, or hybrid threshold profiles) when standards and review bar are met
- [ ] Wrapped share CLI; persistent Serverpod relay

---

## Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial phase checklist |
| 2026-08-13 | Phases 7–10 complete; 1.0.0 tagged; dkg participant deferred v2 |
