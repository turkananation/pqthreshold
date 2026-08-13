# IMPLEMENTATION.md

**pqthreshold** — How to write the first code (module-by-module)

Status: formative specification  
Audience: implementers  
**Read first:** [INDEX.md](INDEX.md)  
**Verify with:** [TOOLING.md](TOOLING.md)

---

## 1. Purpose

[INDEX.md](INDEX.md) tells you **what to read**. [API.md](API.md) defines **public types**. This document tells you **which files to create**, **in what order**, and **which spec section governs each file** — so implementation proceeds without guesswork.

**Rule:** Do not start Phase *N* until Phase *N* docs are read and Phase *N−1* tests pass `dart run tool/verify.dart full`.

---

## 2. Repository layout (target)

```text
lib/
  pqthreshold.dart              # Tier 1 public barrel
  testing.dart                  # Tier 2 only (Phase 3+)
  src/
    params/
      scheme_id.dart
      threshold_params.dart
    errors/
      threshold_exception.dart
    util/
      secret_buffer.dart        # Disposable wipe
    serialization/
      pqth_header.dart
      pqth_codec.dart
    sharing/                    # Phase 2
    scheme/
      feldman/                  # Phase 2
      dkg/                      # Phase 3
      frost/                    # Phase 4
    dkg/                        # Phase 3
    transcript/                 # Phase 3
    signing/                    # Phase 4
    ceremony/                   # Phase 5

test/
  pqthreshold_test.dart         # smoke (planning)
  serialization/                # Phase 1
  vectors/                      # JSON — see TEST_VECTORS.md
  sharing/                      # Phase 2
  dkg/                          # Phase 3
  signing/                      # Phase 4

tool/
  verify.dart
```

Only create directories when their phase starts — avoid empty modules.

---

## 3. Global implementation rules

| Rule | Source |
| ---- | ------ |
| Crypto from pqforge facades first | [SCHEMES.md](SCHEMES.md) §4 |
| Structure from swissarmyknife | [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) |
| Internal `Result`; public throws `ThresholdException` | [API.md](API.md) §5.1 |
| 1-based `participantIndex` | [PARAMS.md](PARAMS.md) §4 |
| All bytes canonical per spec | [SERIALIZATION.md](SERIALIZATION.md), [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) |
| No secrets in logs or transcripts | [SECURITY.md](SECURITY.md) §9 |

### 3.1 Imports (template)

```dart
import 'package:pqforge/pqforge.dart';           // PqBytes, PqClassical, …
import 'package:swissarmyknife/swissarmyknife.dart';
// pointycastle: only via pqforge, comment why — SCHEMES §4
```

---

## 4. Phase 1 — Foundation (start here)

**Docs:** [PARAMS.md](PARAMS.md), [SERIALIZATION.md](SERIALIZATION.md) §3–4.1, [API.md](API.md) §3.1–3.2, [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.1–3.4

### 4.1 `lib/src/params/scheme_id.dart`

- Enum `SchemeId` with `frostEd25519V1` ordinal **1** ([PARAMS.md](PARAMS.md) §2).
- `SchemeId.fromOrdinal(int)` → `SerializationError` if unknown.

### 4.2 `lib/src/params/threshold_params.dart`

- Immutable `ThresholdParams` per [API.md](API.md) §3.1.
- Factory `ThresholdParams.tOfN` uses swissarmyknife `Validator` ([PARAMS.md](PARAMS.md) §6).
- `toBytes` / `fromBytes` per [SERIALIZATION.md](SERIALIZATION.md) §4.1.

### 4.3 `lib/src/errors/threshold_exception.dart`

- Sealed hierarchy per [API.md](API.md) §5.
- Helper `throwFromResult(Result<T, ThresholdException> r)` for barrel.

### 4.4 `lib/src/serialization/pqth_header.dart`

- Encode/decode 8-byte header ([SERIALIZATION.md](SERIALIZATION.md) §3.1).
- Validate magic `PQTH`, `ver == 0x01`.

### 4.5 `lib/src/serialization/pqth_codec.dart`

- `CodecPipeline` for length-prefixed fields ([SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.3).
- Round-trip tests in `test/serialization/pqth_header_test.dart`.

### 4.6 Export

- Export `ThresholdParams`, `SchemeId`, `ThresholdException` types from `lib/pqthreshold.dart` when ready.

### 4.7 Phase 1 done when

- [x] `dart run tool/verify.dart full` passes
- [x] Params reject invalid `t`/`n` per [PARAMS.md](PARAMS.md) §3.2
- [x] Header round-trip tests pass

### 4.8 Phase 1 CLI slice (`bin/pqthreshold.dart`)

- `params validate` / `params export` — [TERMINAL.md](TERMINAL.md) §7
- `inspect` — PQTH header + ThresholdParams; wrapped JSON metadata (no unwrap)
- Tests: `test/cli/pqthreshold_cli_test.dart`
- Version: `dart run tool/version/generate_version.dart` (from `pubspec.yaml`)

---

## 5. Phase 2 — Feldman VSS

**Docs:** [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §4, [FROST_PROFILE.md](FROST_PROFILE.md) §6, [TEST_VECTORS.md](TEST_VECTORS.md) §4.1

### 5.1 `lib/src/scheme/feldman/`

- Polynomial, commitments, verify equation ([FROST_PROFILE.md](FROST_PROFILE.md) §6.2).

### 5.2 `lib/src/sharing/verifiable_secret_sharing.dart`

- `split`, `verifyShare`, `reconstruct` per [API.md](API.md) §4.2.
- Wire helpers for [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §4.1–4.3.

### 5.3 Tests + vectors

- Add `test/vectors/feldman/*.json` per [TEST_VECTORS.md](TEST_VECTORS.md).
- `test/sharing/feldman_test.dart`: `t-1` fails, `t` succeeds.

---

## 6. Phase 3 — DKG

**Docs:** [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3, [CEREMONIES.md](CEREMONIES.md) §5, [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.5

### 6.1 `lib/src/dkg/dkg_state.dart`

- States and events matching [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §3.1.

### 6.2 `lib/src/dkg/ceremony_session.dart`

- `CeremonySession` implementing [API.md](API.md) §4.1.
- `StateMachine` from swissarmyknife.

### 6.3 `lib/src/transcript/transcript.dart`

- [SERIALIZATION.md](SERIALIZATION.md) §4.5.

### 6.4 Tier 2

- `lib/testing.dart`: `DkgSimulator` ([API.md](API.md) §2).

---

## 7. Phase 4 — FROST signing

**Docs:** [FROST_PROFILE.md](FROST_PROFILE.md), [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §5

### 7.1 `lib/src/scheme/frost/`

- H1/H2/H3 with SHA-512 ([FROST_PROFILE.md](FROST_PROFILE.md) §5).
- Round1/Round2 message bytes.

### 7.2 `lib/src/signing/threshold_signer.dart`

- [API.md](API.md) §4.3; verify via `PqClassical.provider.ed25519Verify`.

---

## 8. Phase 5 — Ceremonies

**Docs:** [CEREMONIES.md](CEREMONIES.md), [SERIALIZATION.md](SERIALIZATION.md) §4.6

- `lib/src/ceremony/root_ceremony.dart`, rotation helpers.
- `ContinuityProof` codec.

---

## 9. Definition of done (v1.0)

See [ROADMAP.md](ROADMAP.md) Phase 6 and [TEST_VECTORS.md](TEST_VECTORS.md) §4.

---

## 10. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial implementation guide |
