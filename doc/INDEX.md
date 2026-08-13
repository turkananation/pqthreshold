# Documentation index

**pqthreshold** — Read this first. Implement from these documents in order.

Status: formative specification  
Audience: implementers (no prior context required)

---

## 1. How to use this library of documents

Each file has a single role. **Do not guess** behavior that is not written here or in a linked section. If two documents appear to conflict, resolution order is:

1. **`doc/PROTOCOL_MESSAGES.md`** and **`doc/FROST_PROFILE.md`** for byte-level crypto protocol details  
2. **`doc/SERIALIZATION.md`** for stored object layouts and domain-separation strings  
3. **`doc/PARAMS.md`** for `t`, `n`, indices, and limits  
4. **`doc/API.md`** for public Dart types and Tier 1 / Tier 2 boundaries  
5. **`doc/SCHEMES.md`** for algorithm choices and dependency sourcing  
6. **`doc/CEREMONIES.md`** for operational flows (C1–C6)  
7. **`doc/ARCHITECTURE.md`**, **`doc/INTEGRATION.md`**, **`doc/SECURITY.md`** for structure, stack, and claims  

ADRs in `doc/adr/` record *why* a decision was made; they do not override protocol bytes in (1–3).

---

## 2. Recommended reading order (first time)

| Step | Document | You should know after reading |
| ---- | -------- | ----------------------------- |
| 1 | [ARCHITECTURE.md](ARCHITECTURE.md) | Modules, boundaries, what is in / out of scope |
| 2 | [SCHEMES.md](SCHEMES.md) | v1 algorithms: Feldman VSS, Gennaro DKG, FROST Ed25519 |
| 3 | [PARAMS.md](PARAMS.md) | Valid `t`/`n`, indices, hard limits |
| 4 | [SERIALIZATION.md](SERIALIZATION.md) | `PQTH` header, durable objects, domain strings |
| 5 | [FROST_PROFILE.md](FROST_PROFILE.md) | FROST ciphersuite pin, rounds, combined sig = Ed25519 |
| 6 | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) | On-the-wire DKG / FROST / Feldman message bytes |
| 7 | [API.md](API.md) | Public Dart API; Tier 1 vs Tier 2 |
| 8 | [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) | Where `StateMachine`, `Result`, `Validator` are used |
| 9 | [CEREMONIES.md](CEREMONIES.md) | C1–C6 flows mapped to library calls |
| 10 | [TEST_VECTORS.md](TEST_VECTORS.md) | Test file layout and acceptance criteria |
| 11 | [SECURITY.md](SECURITY.md) | Threat model + **Appendix A** (scheme assumptions) |
| 12 | [INTEGRATION.md](INTEGRATION.md) | Composition with pqforge / applications |
| 13 | [ROADMAP.md](ROADMAP.md) | Implementation phase checklist |
| 14 | [IMPLEMENTATION.md](IMPLEMENTATION.md) | File-level build order (start coding) |
| 15 | [TOOLING.md](TOOLING.md) | CI and `tool/verify.dart` |

---

## 2b. Before first line of code

1. Finish reading steps 1–11 above.
2. Read [IMPLEMENTATION.md](IMPLEMENTATION.md) §4 (Phase 1).
3. Run `dart run tool/verify.dart full` — must pass in spec-only repo.
4. Begin Phase 1 only after both complete.

---

## 3. Implementation phase → documents

| Phase | Goal | Primary docs | Module path |
| ----- | ---- | ------------ | ----------- |
| **0** | Spec complete | This index, ADRs, IMPLEMENTATION, TOOLING | — |
| **1** | Foundation | PARAMS, SERIALIZATION §3–4.1, API §3.1–3.2, SWISSARMYKNIFE §3.1–3.4 | `params/`, `errors/`, `serialization/`, `util/` |
| **2** | Feldman VSS | PROTOCOL_MESSAGES §4, FROST_PROFILE §6 (field), SERIALIZATION §4.2 | `sharing/`, `scheme/feldman/` |
| **3** | DKG | PROTOCOL_MESSAGES §3, CEREMONIES C1, SWISSARMYKNIFE §3.5 | `dkg/`, `transcript/`, `scheme/dkg/` |
| **4** | FROST signing | FROST_PROFILE, PROTOCOL_MESSAGES §5, SERIALIZATION §4.4 | `signing/`, `scheme/frost/` |
| **5** | Ceremonies | CEREMONIES, API §4.4, SERIALIZATION §4.6 ContinuityProof | `ceremony/` |
| **6** | Release | TEST_VECTORS, SECURITY Appendix A, ROADMAP Phase 6 | `tool/verify.dart`, CI |

---

## 4. Ceremony → documents

| Ceremony | Flow doc | Protocol doc | API entry points |
| -------- | -------- | ------------ | ---------------- |
| **C1** Root DKG | CEREMONIES §5 | PROTOCOL_MESSAGES §3 | `CeremonySession`, `RootCeremony` |
| **C2** Dealer VSS | CEREMONIES §6 | PROTOCOL_MESSAGES §4 | `VerifiableSecretSharing.split/verifyShare` |
| **C3** Threshold sign | CEREMONIES §7 | PROTOCOL_MESSAGES §5, FROST_PROFILE | `ThresholdSigner.*` |
| **C4** Recovery | CEREMONIES §8 | PROTOCOL_MESSAGES §4 (reconstruct) | `VerifiableSecretSharing.reconstruct` |
| **C5** Rotation | CEREMONIES §9 | SERIALIZATION §4.6, PROTOCOL_MESSAGES §6 | `RotationCeremony`, C1 + C3 |
| **C6** Refresh | CEREMONIES §10 | — (v2, not v1) | — |

---

## 5. Dependency split (quick reference)

| Need | Package | Doc |
| ---- | ------- | --- |
| SHA-256, HMAC, length-prefixed bytes, CSPRNG | pqforge (`PqBytes`, `PqRandom`) | SCHEMES §4 |
| Ed25519 sign/verify (combined signature) | pqforge (`PqClassical.provider`) | FROST_PROFILE §7 |
| Group/scalar math (VSS/DKG/FROST internals) | pointycastle via pqforge export (last resort) | SCHEMES §4 |
| State machines, Result, Validator, CodecPipeline | swissarmyknife | SWISSARMYKNIFE |

---

## 6. Glossary (consistent terms)

| Term | Meaning |
| ---- | ------- |
| **ceremonyId** | 16 random bytes; binds all objects and messages for one run |
| **participantIndex** | Integer **1..n**; used as Shamir evaluation point **x = index** |
| **participantId** | UTF-8 string label (officer name, device id); not used in curve math |
| **t** | Threshold; minimum shares required |
| **n** | Total participants |
| **Tier 1** | Production multi-party APIs (`CeremonySession`) |
| **Tier 2** | In-process simulation only (`DkgSimulator`) |
| **combined signature** | 64-byte Ed25519 signature after FROST `combine` |
| **verificationData** | Feldman commitment vector or DKG public material on a `Share` |

---

## 7. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial index; links PROTOCOL_MESSAGES, FROST_PROFILE, PARAMS, TEST_VECTORS |
