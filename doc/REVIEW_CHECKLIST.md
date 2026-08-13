# Independent review checklist

**pqthreshold** — Cryptographic and implementation review before production use

Status: operator checklist (Phase 6)  
Use with [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) and [SECURITY.md](SECURITY.md).

---

## 1. Scope

Review covers v1 Tier 1 surface (`lib/pqthreshold.dart`) for scheme **`frostEd25519V1`**:

- Feldman VSS (dealer-based sharing)
- Gennaro DKG (C1)
- FROST threshold signing (C3)
- Continuity proofs (C5 rotation evidence)
- PQTH serialization (`ver=0x01`)

Tier 2 simulators in `lib/testing.dart` are **test harness only** — not in scope for production deployment review unless copied into application code.

---

## 2. Protocol and specification

- [ ] [FROST_PROFILE.md](FROST_PROFILE.md) matches implementation (`lib/src/scheme/frost/`)
- [ ] [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) wire layouts match codecs
- [ ] [SERIALIZATION.md](SERIALIZATION.md) §4 object layouts match round-trip tests
- [ ] Domain-separation strings in §5 are applied consistently
- [ ] Ed25519 challenge (H2) shape matches RFC 8032 / FROST-Ed25519 for pqforge verify path

---

## 3. Cryptographic assumptions

- [ ] Discrete log hardness on Ed25519 curve (Feldman, DKG, FROST)
- [ ] Honest majority: at least `t` of `n` participants honest during DKG and signing
- [ ] Secure channels and participant authentication are **application-provided** (out of scope for library)
- [ ] Share material at rest protected by platform secure storage (application responsibility)

---

## 4. Implementation review

- [ ] No secret scalars in transcripts or logs ([SECURITY.md](SECURITY.md) §9)
- [ ] `SecretBuffer` wipe on combine / dispose paths
- [ ] Fail-closed: `t-1` shares, wrong ceremony, bad partials throw before leaking material
- [ ] Constant-time comparisons for fingerprints and ceremony IDs where specified
- [ ] Randomness from `PqRandom.generator` (document FIPS/module override if required)
- [ ] Dependencies: only `pqforge` + `swissarmyknife` at runtime ([adr/002-runtime-dependencies.md](adr/002-runtime-dependencies.md))

---

## 5. Test evidence

- [ ] `dart run tool/verify.dart full` passes on release commit
- [ ] All [TEST_VECTORS.md](TEST_VECTORS.md) §4 acceptance criteria pass
- [ ] JSON vectors under `test/vectors/` regenerated with fixed deterministic RNG where applicable
- [ ] Negative tests: insufficient shares, wrong message, wrong ceremony, tampered share

---

## 6. Operational readiness

- [ ] [CEREMONIES.md](CEREMONIES.md) flows understood by operators
- [ ] [INTEGRATION.md](INTEGRATION.md) anti-patterns reviewed with application team
- [ ] Recovery / reconstruction (C4) treated as high-privilege, rare, audited
- [ ] Rotation (C5) includes continuity proof verification in relying-party code

---

## 7. Sign-off

| Role | Name | Date | Notes |
| ---- | ---- | ---- | ----- |
| Implementer | | | |
| Cryptographic reviewer | | | |
| Security / ops | | | |

**Review status:** ☐ Not started · ☐ In progress · ☐ Complete with findings · ☐ Complete, no blockers

Findings and remediations: link issue tracker or attach report.

---

## Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial independent review checklist (Phase 6) |
