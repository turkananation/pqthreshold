# SLH_DSA_THRESHOLD_PROFILE.md

**pqthreshold** — Threshold SLH-DSA profile (v2, deferred)

Status: placeholder (M5+)  
Audience: implementers  
Prerequisites: [ADR-004](adr/004-pq-threshold-schemes.md), FIPS 205

---

## 1. Goal

Same verifier-compatibility pattern as ML-DSA: combined signatures must verify with pqforge / pqcrypto **SLH-DSA** paths without threshold-specific application code.

Target identifier: `SchemeId.slhDsa128fThresholdV1` (ordinal `0x0005`).

---

## 2. Why deferred after ML-DSA

SLH-DSA signing is **hash-tree / WOTS+** structured. Threshold constructions differ from lattice MPC (ML-DSA) and from Schnorr/FROST. v2 prioritizes **ML-DSA-65** as the primary PQ organizational root; SLH-DSA threshold follows once ML-DSA review gates pass.

---

## 3. Planned scope (draft)

| Item | Notes |
| ---- | ----- |
| Parameter set | SLH-DSA-SHAKE-128f (align with pqforge default) |
| Max `n` | 8 (same small-set policy as ML-DSA) |
| C1 / C3 | Separate profile; **no reuse** of FROST or ML-DSA wire messages |
| PQTH kind | `0x09` `SlhDsaPublicKey` (reserved) |

---

## 4. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Placeholder for ADR-004 M1 |
