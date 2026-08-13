# TEST_VECTORS.md

**pqthreshold** — Test vector layout and acceptance criteria

Status: formative specification  
Audience: implementers  
Prerequisites: [FROST_PROFILE.md](FROST_PROFILE.md), [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md), [PARAMS.md](PARAMS.md)

---

## 1. Purpose

Defines **where** vectors live, **how** they are formatted, and **when** tests pass. Implementers add files under `test/vectors/` following this layout.

---

## 2. Directory layout

```text
test/
  vectors/
    README.md                    # pointer to this doc
    feldman/
      2of3_valid.json
      2of3_insufficient.json     # t-1 must fail
    dkg/
      2of3_simulated.json
      3of5_simulated.json
    frost/
      signing_2of3.json
      draft_ed25519/             # optional: imported draft vectors
  sharing/
    feldman_test.dart            # loads test/vectors/feldman/*
  dkg/
    dkg_simulation_test.dart
  signing/
    frost_test.dart
```

---

## 3. File format (JSON v1)

Each vector file:

```json
{
  "format": "pqthreshold-test-vector-v1",
  "scheme": "frostEd25519V1",
  "description": "human-readable",
  "params": { "t": 2, "n": 3 },
  "ceremonyId": "hex32",
  "inputs": { },
  "expected": { },
  "notes": "optional"
}
```

- All byte values: **lowercase hex** strings.
- `ceremonyId`: 32 hex chars (16 bytes).
- Do **not** commit real production secrets; use deterministic seeds in tests only.

---

## 4. Acceptance criteria by area

### 4.1 Feldman VSS (`test/vectors/feldman/`)

| Test | Expected |
| ---- | -------- |
| `2of3_valid` | Reconstruct with shares 1+2 succeeds; secret matches `expected.secret` |
| `2of3_insufficient` | Reconstruct with any **1** share → `InsufficientShares` |
| Malformed commitment | `verifyShare` → `InconsistentShares` |

### 4.2 DKG (`test/vectors/dkg/`)

| Test | Expected |
| ---- | -------- |
| `2of3_simulated` | All parties derive same `jointPublicKey` hex |
| `3of5_simulated` | Same; each party distinct `share` hex |
| Malicious share (optional vector) | Complaint → abort or exclude |

Simulation uses Tier 2 harness ([API.md](API.md) §2).

### 4.3 FROST signing (`test/vectors/frost/`)

| Test | Expected |
| ---- | -------- |
| `signing_2of3` | `combine` → `expected.signature` (64-byte hex) |
| Verify | `PqClassical.provider.ed25519Verify` returns **true** |
| Wrong message | Verify **false** |
| **t-1** partials | `combine` → `InvalidPartialSignature` |

Cryptography profile: [FROST_PROFILE.md](FROST_PROFILE.md).

### 4.4 Serialization round-trips

For each object in [SERIALIZATION.md](SERIALIZATION.md) §4:

- `toBytes` → `fromBytes` → equal canonical bytes
- Wrong `ceremonyId` on decode → `WrongCeremony`

Covered in `test/serialization/pqth_roundtrip_test.dart`.

### 4.5 Ceremony / rotation (`test/vectors/ceremony/`)

| Test | Expected |
| ---- | -------- |
| `rotation_2of3` | Continuity signature matches `expected.continuitySignature`; verify under old key **true** |
| New joint key | Matches `expected.newJointPublicKey` |

Regenerate: `dart run tool/generate_rotation_vectors.dart`.

---

## 5. Generating vectors (implementers)

1. Use fixed `PqRandom.generator` seed in test-only code for reproducibility.
2. Run generator tool (future: `dart run tool/generate_vectors.dart`) — until then, inline in test setup.
3. Record `jointPublicKey`, `signature`, and hashes in JSON.
4. Review: no private keys in vectors unless labeled **test-only**.

---

## 6. CI gate

`dart run tool/verify.dart full` runs analyze, tests, doc manifest, and phase test dirs when present ([TOOLING.md](TOOLING.md)).

Release **0.x → 1.0** blocked until all §4 criteria pass for `frostEd25519V1`.

---

## 7. Cross-references

| Topic | Document |
| ----- | -------- |
| Profile | [FROST_PROFILE.md](FROST_PROFILE.md) §9 |
| Wire messages | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) |
| ROADMAP Phase 6 | [ROADMAP.md](ROADMAP.md) |

---

## 8. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial vector layout and acceptance criteria |
