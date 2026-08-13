# SWISSARMYKNIFE.md

**pqthreshold** — How `swissarmyknife` is used (engineering layer)

Status: formative specification  
Audience: implementers  
Prerequisites: `doc/SCHEMES.md`, `doc/adr/002-runtime-dependencies.md`, [INDEX.md](INDEX.md)

---

## 1. Purpose

`pqthreshold` splits dependencies by **concern**, not by “how many packages we can avoid”:

| Package | Owns |
| ------- | ---- |
| **`pqforge`** | Cryptography — hashing, randomness, Ed25519, symmetric helpers, pointycastle last resort |
| **`swissarmyknife`** | Engineering structure — state machines, `Result`, validation, codecs, bytes UX, disposal, tuples |

Threshold protocols need **both**: correct math (pqforge) and explicit, auditable control flow (swissarmyknife). This document maps swissarmyknife APIs to pqthreshold modules so usage stays consistent and reviewable.

---

## 2. Import rule

```dart
import 'package:pqforge/pqforge.dart';       // crypto paths only
import 'package:swissarmyknife/swissarmyknife.dart'; // structure & utilities
```

Do **not** use swissarmyknife for SHA-256, HMAC, Ed25519, or HKDF — those stay on pqforge facades.

Do **not** use pqforge for DKG round state machines or composable param validation — those stay on swissarmyknife.

---

## 3. Module mapping

### 3.1 `params/` — `ThresholdParams`

| API | Usage |
| --- | ----- |
| `Validator<(int t, int n)>` or custom `Validator<ThresholdParamsDraft>` | Composable rules: `1 ≤ t ≤ n`, scheme max `n`, non-empty ceremony binding |
| `Result<ThresholdParams, InvalidParamsDetail>` | Construction without throwing; map to `InvalidParams` at public barrel |

```dart
// Illustrative
final v = Validator<(int, int)>()
    .custom((p) => p.$1 >= 1, 't must be ≥ 1')
    .custom((p) => p.$1 <= p.$2, 't must be ≤ n');
```

### 3.2 `errors/` — boundary mapping

| API | Usage |
| --- | ----- |
| `Result<T, ThresholdException>` internally | Protocol steps return explicit failure |
| `Result.combine` | Collecting partial signatures / share sets — first failure wins |
| Public API | Still throws sealed `ThresholdException` (or returns `Result` only where ADR allows — default: throw at barrel) |

Internal code prefers `Result`; the public barrel converts to `ThresholdException` for fail-closed, exhaustive handling.

### 3.3 `serialization/` — wire formats

| API | Usage |
| --- | ----- |
| `CodecPipeline<Share, Uint8List>` | Staged encode: header → params → payload → finalize |
| `CodecPipeline.decodeResult` | Parse without throwing; map to `SerializationError` |
| `Uint8ListKnife.toHexString` | Debug logging and test failure messages (**never** log secrets) |

Binary layout rules remain in `doc/SERIALIZATION.md`; swissarmyknife pipelines implement the stages.

### 3.4 `util/` — bytes and lifecycle

| API | Usage |
| --- | ----- |
| `Uint8List.contentEquals` | Non-protocol equality checks (e.g. ceremony ID, participant ID bytes in tests) |
| `PqBytes.constantTimeEquals` (pqforge) | **Cryptographic** comparisons — signatures, MACs, scalar encodings after decode |
| `Disposable` / `DisposeBag` | `CeremonySession`, ephemeral reconstruct buffers — wipe on finalize/abort |
| `Option<T>` | Optional ceremony context, optional verify attachments |

**Rule:** If the comparison guards a cryptographic decision, use **pqforge** `PqBytes.constantTimeEquals`. If it guards structural/state logic, **swissarmyknife** `contentEquals` is fine.

### 3.5 `dkg/` + `ceremony/` — round state machines

| API | Usage |
| --- | ----- |
| `StateMachine<DkgState, DkgEvent>` | Per-participant DKG lifecycle |
| `StateTransitionRule` + guards | Invalid round / replay → `Result.failure` → `CeremonyAborted` |
| `StateAction` | Append to transcript on successful transition (public data only) |

Illustrative states:

```text
setup → round1Contribution → round2Distribution → round3Finalize → complete
                              ↘ complaint ↗                      ↘ aborted
```

`RootCeremony`, `RotationCeremony` orchestrators compose one `StateMachine` per participant (Tier 1).

### 3.6 `signing/` — threshold sign/combine

| API | Usage |
| --- | ----- |
| `Result<PartialSignature, ThresholdException>` | `signPartial` internal steps |
| `Result.combine` | Merge validation of partial list before FROST combine |
| `Validator<List<PartialSignature>>` | Count ≥ t, distinct signer indices, matching ceremony binding |
| `Tuple2` / `Tuple3` | Multi-value returns from scheme layer without ad-hoc records |

Combined signature **verification** uses `PqClassical.provider.ed25519Verify` (pqforge), not swissarmyknife.

### 3.7 `sharing/` — VSS

| API | Usage |
| --- | ----- |
| `Result<List<Share>, ThresholdException>` | Dealer split |
| `Validator<Share>` | Index range, ceremony binding before verify |
| `Pipeline` / `Pipeline.async` | Optional fluent split → distribute → verify chain in tests |

### 3.8 `transcript/`

| API | Usage |
| --- | ----- |
| `Result<void, TranscriptMismatch>` | Hash-chain append and seal |
| `Uint8List.toHexString` | Audit log display of hashes (not secrets) |
| Immutable append-only list + `functionalValuesEqual` patterns for test assertions |

### 3.9 `scheme/` — internal protocol engine

| API | Usage |
| --- | ----- |
| `Tuple2`, `Tuple3` | Round handler outputs (message out + state delta) |
| `Result` | Every FROST/Feldman step |
| `Lazy<T>` | Expensive verification data parsed once per share |

### 3.10 Tests and simulation (Tier 2)

| API | Usage |
| --- | ----- |
| `Result.runCatching` / `runCatchingAsync` | Simulation harness |
| `benchmark` / `benchmarkAsync` | DKG/sign perf gates in `tool/verify.dart` |
| `Uint8List.toHexString` | Vector diff output |

---

## 4. Explicit non-usage

Do **not** use swissarmyknife for:

| Feature | Use instead |
| ------- | ----------- |
| SHA-256, HMAC, HKDF | `PqBytes`, `PqSymmetricPrimitives` (pqforge) |
| Ed25519 sign/verify | `PqClassical.provider` (pqforge) |
| CSPRNG | `PqRandom` / `PqBytes.randomBytes` (pqforge) |
| HTTP / transport | Application (out of scope) |
| `EventBus` for ceremony transport | Application — library stays transport-agnostic |
| `SafeJson` for durable share storage | Binary format in `doc/SERIALIZATION.md` |

---

## 5. Layer diagram

```text
┌─────────────────────────────────────────────────────────┐
│  ceremony / dkg / signing / sharing  (public & src)     │
│  swissarmyknife: StateMachine, Result, Validator, …     │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  scheme/ (FROST, Feldman, Gennaro math)                 │
│  pqforge-first crypto; pointycastle last resort         │
└───────────────────────────┬─────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────┐
│  pqforge: PqBytes, PqRandom, PqClassical, …            │
└─────────────────────────────────────────────────────────┘
```

---

## 6. Review checklist

When reviewing PRs, confirm:

- [ ] New DKG/ceremony flow uses `StateMachine` or documents why not
- [ ] Fallible internal steps return `Result`, not bare exceptions
- [ ] Param/share validation uses `Validator` or sealed checks with same explicitness
- [ ] Secret-bearing types use `Disposable` / explicit wipe on abort
- [ ] No swissarmyknife crypto (hash/sign/random)
- [ ] No pqforge `StateMachine`-style ad-hoc enums without swissarmyknife where a machine fits

---

## 7. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial swissarmyknife usage map |
