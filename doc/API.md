# API.md

**pqthreshold** — Public API contract (formative)

Status: formative specification — shapes below are targets for v1; breaking changes require semver and CHANGELOG notes  
Audience: integrators, implementers  
**Read first:** [INDEX.md](INDEX.md)  
Prerequisites: `doc/ARCHITECTURE.md`, `doc/SCHEMES.md`, `doc/PARAMS.md`, `doc/CEREMONIES.md`

---

## 1. Purpose

This document defines the **intended public surface** of `pqthreshold`, split into two tiers so production multi-party flows are not confused with in-process simulation helpers.

The README quick start illustrates Tier 2 for brevity. **Production integrations must use Tier 1.**

---

## 2. API tiers

### Tier 1 — Production (multi-party)

Per-participant state machines. The application provides transport and authentication between parties.

| Component | Role |
| --------- | ---- |
| `CeremonySession` | Drives one participant through DKG rounds |
| `ThresholdSigner.signPartial` | One share → one partial signature |
| `ThresholdSigner.combine` | ≥ t partials → combined signature |
| `ThresholdSigner.verify` | Joint public key + message + signature |
| `VerifiableSecretSharing` | Dealer split / participant verify / reconstruct |
| `Transcript` | Append-only audit log |

### Tier 2 — Simulation / testing (in-process)

Convenience APIs that run all parties in one process. **Not for production ceremonies.**

| Component | Role |
| --------- | ---- |
| `DkgSimulator.run` | All parties, one call — tests and docs only |
| `@visibleForTesting` exports | Exposed only for test packages |

Tier 2 APIs are annotated in dartdoc and may live under `package:pqthreshold/testing.dart` if needed to signal non-production use.

---

## 3. Core types

### 3.1 ThresholdParams

```dart
final class ThresholdParams {
  const ThresholdParams._({
    required this.t,
    required this.n,
    required this.scheme,
  });

  final int t;
  final int n;
  final SchemeId scheme;

  /// Validates constraints; throws [InvalidParams] on failure.
  factory ThresholdParams.tOfN({
    required int t,
    required int n,
    SchemeId scheme = SchemeId.frostEd25519V1,
  });

  Uint8List toBytes();
  factory ThresholdParams.fromBytes(Uint8List bytes);
}
```

### 3.2 Share

```dart
final class Share {
  final ThresholdParams params;
  final Uint8List ceremonyId;
  final String participantId;
  final int index; // 1..n

  Uint8List toBytes();
  factory Share.fromBytes(Uint8List bytes);
  // Opaque secret material — no public getters for scalar value
}
```

### 3.3 PublicKey

```dart
final class PublicKey {
  final ThresholdParams params;
  final Uint8List ceremonyId;
  final Uint8List bytes; // 32-byte Ed25519 in v1

  Uint8List toBytes();
  factory PublicKey.fromBytes(Uint8List bytes);

  /// Fingerprint for binding partial signatures.
  Uint8List get fingerprint; // SHA-256 of canonical encoding
}
```

### 3.4 PartialSignature

```dart
final class PartialSignature {
  final Uint8List ceremonyId;
  final int signerIndex;
  final Uint8List bytes;

  Uint8List toBytes();
  factory PartialSignature.fromBytes(Uint8List bytes);
}
```

### 3.5 Transcript

```dart
final class Transcript {
  final Uint8List ceremonyId;
  final ThresholdParams params;

  void appendRound({required int round, required int senderIndex, required Uint8List messageBytes});
  Uint8List seal({PublicKey? finalPublicKey, required bool success, String? abortReason});
  bool verify();
  Uint8List toBytes();
  factory Transcript.fromBytes(Uint8List bytes);
}
```

---

## 4. Tier 1 protocol APIs

### 4.1 DKG — CeremonySession

```dart
abstract interface class CeremonySession {
  factory CeremonySession.create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int participantIndex,
  });

  /// Current protocol round (0 = setup).
  int get round;

  /// Process messages received from peers; returns messages to send.
  List<DkgMessage> processInbox(Iterable<DkgMessage> inbox);

  /// True when the session can finalize.
  bool get isComplete;

  /// Output share and public key, or throw [CeremonyAborted].
  ({Share share, PublicKey publicKey, Transcript transcript}) finalize();
}
```

`DkgMessage` — typed wrapper for protocol envelopes defined in [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md) §2–3.

### 4.2 VSS — VerifiableSecretSharing

```dart
abstract final class VerifiableSecretSharing {
  /// Dealer: split secret into n verifiable shares (C2).
  static ({List<Share> shares, List<Uint8List> verificationData}) split({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required Uint8List secret,
  });

  /// Recipient: verify a share against public verification data.
  static void verifyShare({
    required Share share,
    required List<Uint8List> verificationData,
  });

  /// Quorum reconstruct (C4-A — high privilege).
  static Uint8List reconstruct({
    required List<Share> shares,
  });
}
```

### 4.3 Threshold signing

```dart
abstract final class ThresholdSigner {
  static Future<PartialSignature> signPartial({
    required Share share,
    required Uint8List message,
    Uint8List? context,
  });

  static Uint8List combine({
    required List<PartialSignature> partials,
    required PublicKey publicKey,
    required Uint8List message,
    Uint8List? context,
  });

  static bool verify({
    required PublicKey publicKey,
    required Uint8List message,
    required Uint8List signature,
    Uint8List? context,
  });
}
```

`verify` delegates to **`PqClassical.provider.ed25519Verify`** for v1 (not raw pointycastle).

### 4.4 Ceremony helpers

```dart
abstract final class RootCeremony {
  /// Tier 1: one participant’s session factory.
  static CeremonySession startSession({...});

  /// Tier 2: in-process simulation only.
  @visibleForTesting
  static Future<({List<Share> shares, PublicKey publicKey, Transcript transcript})>
      simulate(ThresholdParams params, {int? seed});
}
```

Similar patterns for `ThresholdSigningCeremony` (C3) and `RotationCeremony` (C5) — orchestration only; crypto in `signing/` and `dkg/`.

---

## 5. Error model

```dart
sealed class ThresholdException implements Exception {
  const ThresholdException(this.message);
  final String message;
}

final class InvalidParams extends ThresholdException { ... }
final class InsufficientShares extends ThresholdException { ... }
final class InconsistentShares extends ThresholdException { ... }
final class InvalidPartialSignature extends ThresholdException { ... }
final class TranscriptMismatch extends ThresholdException { ... }
final class CeremonyAborted extends ThresholdException { ... }
final class WrongCeremony extends ThresholdException { ... }
final class SerializationError extends ThresholdException { ... }
```

No API returns partial secrets on error.

### 5.1 Internal vs public error flow

| Layer | Pattern | Doc |
| ----- | ------- | --- |
| `lib/src/**` | swissarmyknife `Result<T, ThresholdException>` | [SWISSARMYKNIFE.md](SWISSARMYKNIFE.md) §3.2 |
| `lib/pqthreshold.dart` (public) | Throws sealed `ThresholdException` | This section |
| Tier 2 `testing.dart` | May expose `Result` for harness convenience | Annotate in dartdoc |

Implementers: never return `Result` from public Tier 1 factories without an ADR.

---

## 6. Public barrel exports

`lib/pqthreshold.dart` exports:

- All Tier 1 types and functions above
- `SchemeId`, `ThresholdException` hierarchy
- **Not** Tier 2 simulation APIs (those in `pqthreshold/testing.dart` if split)

Internal modules under `lib/src/` remain private.

---

## 7. Stability guarantees (target for 1.0)

| Before 1.0 (current) | At 1.0 |
| -------------------- | ------ |
| API may change with minor version bumps | Tier 1 surface frozen except additive changes |
| Serialization format may iterate with `ver` byte | `ver=0x01` frozen; new versions additive |
| Simulation APIs may move packages | `testing.dart` stable for test consumers |

---

## 8. Relationship to pqforge

- `pqthreshold` uses **pqforge** for crypto and **swissarmyknife** for protocol structure (`doc/SWISSARMYKNIFE.md`).
- Applications depend on **both** packages for full stack integration (`doc/INTEGRATION.md`).
- `ThresholdSigner.verify` output must be acceptable to pqforge Ed25519 verify paths without adapter code in v1.

---

## 9. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial API contract; Tier 1 vs Tier 2 split |
