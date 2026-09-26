# pqthreshold

High-assurance pure-Dart threshold cryptography and distributed key-management primitives

[![pub package](https://img.shields.io/pub/v/pqthreshold.svg)](https://pub.dev/packages/pqthreshold)
[![likes](https://img.shields.io/pub/likes/pqthreshold)](https://pub.dev/packages/pqthreshold/score)
[![points](https://img.shields.io/pub/points/pqthreshold)](https://pub.dev/packages/pqthreshold/score)
[![license](https://img.shields.io/github/license/turkananation/pqthreshold)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-%5E3.10-0175C2?logo=dart&logoColor=white)](https://dart.dev)

> Zero native dependencies. Verifiable secret sharing, distributed key generation (DKG), threshold signatures, and multi-party ceremony building blocks for organizational roots, enclave recovery, and self-custodial multi-device setups.

**Documentation** · [Getting started](doc/GETTING_STARTED.md) · [Website](https://turkananation.github.io/pqthreshold/) · [Wiki](https://github.com/turkananation/pqthreshold/wiki) · [API reference](https://pub.dev/documentation/pqthreshold/latest/) · [Security model](doc/SECURITY.md)

---

## Why pqthreshold exists

Most high-assurance systems eventually need a root or recovery key that **no single device or person should ever hold in full**.  
Classic answers rely on hardware security modules, foreign libraries, or trusted dealers.  

`pqthreshold` gives pure-Dart programs the same capability:

- Generate a key so that it is born already threshold-shared
- Sign only when a quorum of parties collaborates
- Recover or rotate without ever reconstructing the full secret on one machine
- Run the entire ceremony on Dart / Flutter / server with zero FFI

It is designed as the natural companion to [`pqcrypto`](https://pub.dev/packages/pqcrypto) and [`pqforge`](https://pub.dev/packages/pqforge): single-party post-quantum primitives on one side, distributed key management on the other.

---

## Core principles

| Principle | Meaning |
| ----------- | --------- |
| **No single point of secret** | The full private key never exists in one place after the ceremony |
| **Pure Dart** | Zero native dependencies, works on VM, Flutter, and web (where the algorithms permit) |
| **Auditable by construction** | Clear APIs, explicit security levels, checked-in test vectors where applicable |
| **Ceremony-oriented** | APIs match real organizational workflows (root generation, recovery, rotation) |
| **Composable** | Plays cleanly with hybrid post-quantum stacks (ML-DSA / ML-KEM + classical) |

---

## Features

### Verifiable Secret Sharing (VSS)

- Share a secret among *n* parties so that any *t* can reconstruct it
- Verifiable shares (parties can check they received consistent material)
- Support for both classic and modern constructions suitable for key management

### Distributed Key Generation (DKG)

- Generate a public key + threshold private shares **without a trusted dealer**
- Ideal for enclave root keys and multi-officer organizational signing keys
- Transcript and verification helpers for auditability

### Threshold Signatures

- Produce a valid signature only when a quorum of share holders collaborates
- Compatible with common verification paths (single public key on the verifier side)
- Designed for integration with existing signature verification in `pqforge` / application code

### Ceremony & recovery helpers

- Multi-party root ceremony flows
- Secure recovery and rotation patterns
- Explicit handling of participant addition / removal (where the underlying scheme allows)

### Engineering qualities

- Sealed error types and clear failure modes
- Deterministic test vectors and property-based tests where meaningful
- Documentation that states exactly what is and is not claimed
- No network layer — you supply the transport; the library only does cryptography

---

## Quick start

> **Illustrative only (Tier 2 simulation API).** Production ceremonies use per-participant `CeremonySession` state machines with application-provided transport. See [`doc/API.md`](doc/API.md).

```dart
import 'package:pqthreshold/pqthreshold.dart';

Future<void> main() async {
  // Example: 3-of-5 threshold setup using the in-process simulator.
  final params = ThresholdParams.tOfN(t: 3, n: 5);

  // In-process simulation — NOT for production multi-device ceremonies
  final dkg = await DkgSimulator.run(params);
  final publicKey = dkg.publicKey;
  final shares = dkg.shares;

  final message = Uint8List.fromList([1, 2, 3]);
  final partials = <PartialSignature>[];
  for (final share in shares.take(params.t)) {
    partials.add(await ThresholdSigner.signPartial(share: share, message: message));
  }

  final signature = ThresholdSigner.combine(
    partials: partials,
    publicKey: publicKey,
    message: message,
  );
  final valid = ThresholdSigner.verify(
    publicKey: publicKey,
    message: message,
    signature: signature,
  );
  print('threshold signature valid: $valid');
}
```

> The simulator is useful for tests and demonstrations. Production ceremonies
> use per-participant `CeremonySession` state machines with application-provided
> transport; see [`doc/API.md`](doc/API.md).

---

## Security model (read this)

`pqthreshold` provides **cryptographic primitives and ceremony building blocks**.  
It does **not**:

- Replace a full key-management system or HSM
- Provide network transport, authentication of participants, or secure channels
- Claim FIPS 140 / CMVP validation
- Protect against compromised participants beyond the threshold guarantee
- Solve endpoint security (malware on a participant device is out of scope)

**You** are responsible for:

- Authenticating the parties that take part in a ceremony
- Protecting shares at rest and in transit
- Choosing appropriate thresholds for your threat model
- Combining the primitives with hybrid post-quantum signatures / KEMs when long-term security is required

See [SECURITY.md](SECURITY.md) for vulnerability reporting and [doc/SECURITY.md](doc/SECURITY.md) for the full threat model, assumptions, and claim boundaries.

---

## Integration with the rest of the stack

| Package | Role |
| --------- | ------ |
| [`pqcrypto`](https://pub.dev/packages/pqcrypto) | Single-party ML-KEM / ML-DSA / SLH-DSA primitives |
| [`pqforge`](https://pub.dev/packages/pqforge) | Application recipes, hybrid sealing, sessions, envelopes |
| **`pqthreshold`** | Distributed key generation, threshold signing, multi-party ceremonies |
| Application (e.g. Panthalassa Vault) | Enclave roots, recovery policies, organizational governance |

Typical pattern:

1. Use `pqthreshold` to run a DKG or threshold ceremony for an organizational / enclave root.
2. Use the resulting public key and threshold signing capability with `pqforge` verification paths.
3. Keep individual device keys and day-to-day sealing on the existing `pqcrypto` / `pqforge` single-party path.

---

## When to use it

- Organizational or enclave root keys that must not live on one laptop
- Multi-officer approval for high-value signatures
- Self-custodial recovery that does not rely on a single backup file
- Multi-device personal setups where no single device holds the full secret
- Any design that already says “threshold root” or “Shamir recovery” in the specification

When **not** to use it:

- Simple single-user key pairs (use `pqcrypto` / `pqforge` directly)
- Situations that require certified HSM-backed keys under a specific compliance regime
- General-purpose arbitrary MPC (this library is intentionally focused on key management)

---

## Package status

| Area | Status |
| ------ | -------- |
| Specification | **Complete** — [doc/INDEX.md](doc/INDEX.md) |
| Implementation | **Stable Tier 1** — VSS, DKG, FROST signing, ceremony helpers, PQTH serialization, and CLI |
| Verify locally | `dart run tool/verify.dart full` |
| CI | `.github/workflows/ci.yml` → `verify quick` |

The package follows the same evidence-oriented style as `pqcrypto`: clear documentation of what is implemented, what is tested, and what is explicitly not claimed.

---

## Installation

```yaml
dependencies:
  pqthreshold: ^1.0.0
```

```bash
dart pub get
# or
flutter pub get
```

### Terminal (CLI)

The CLI ships parameter, inspection, VSS, DKG, signing, and ceremony workflows. Pair with [`pqforge`](https://pub.dev/packages/pqforge) for device keys — see [doc/TERMINAL.md](doc/TERMINAL.md).

```bash
dart pub global activate pqthreshold   # when published
# or from clone:
dart run pqthreshold --help

pqthreshold params validate --t 2 --n 3
pqthreshold params export --t 3 --n 5 --out ceremony/params.pqth
pqthreshold inspect --in ceremony/params.pqth
```

---

## Documentation map

**Implementers: start at [doc/INDEX.md](doc/INDEX.md).**

| Document | Purpose |
| ---------- | --------- |
| [doc/INDEX.md](doc/INDEX.md) | **Reading order and phase map** |
| [doc/GETTING_STARTED.md](doc/GETTING_STARTED.md) | **Run tests, example, ceremony flows** |
| [README.md](README.md) | This file |
| [SECURITY.md](SECURITY.md) | Vulnerability reporting |
| [doc/SECURITY.md](doc/SECURITY.md) | Threat model & claim boundaries |
| [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) | Internal structure |
| [doc/SCHEMES.md](doc/SCHEMES.md) | v1 algorithm choices |
| [doc/PARAMS.md](doc/PARAMS.md) | t/n limits and participant indices |
| [doc/SERIALIZATION.md](doc/SERIALIZATION.md) | Stored object formats |
| [doc/FROST_PROFILE.md](doc/FROST_PROFILE.md) | FROST Ed25519 ciphersuite |
| [doc/PROTOCOL_MESSAGES.md](doc/PROTOCOL_MESSAGES.md) | Protocol message bytes |
| [doc/API.md](doc/API.md) | Public API contract (Tier 1 vs Tier 2) |
| [doc/TEST_VECTORS.md](doc/TEST_VECTORS.md) | Test vector layout |
| [doc/IMPLEMENTATION.md](doc/IMPLEMENTATION.md) | Module build order (first code) |
| [doc/TOOLING.md](doc/TOOLING.md) | CI and verify.dart |
| [doc/RELEASE_CHECKLIST.md](doc/RELEASE_CHECKLIST.md) | v1.0 release gate |
| [doc/CEREMONIES.md](doc/CEREMONIES.md) | Recommended multi-party flows |
| [doc/INTEGRATION.md](doc/INTEGRATION.md) | Working with pqcrypto / pqforge |
| [doc/TERMINAL.md](doc/TERMINAL.md) | Terminal / CLI workflows with pqforge |
| [doc/SWISSARMYKNIFE.md](doc/SWISSARMYKNIFE.md) | swissarmyknife usage map (state machines, Result, …) |
| [doc/ROADMAP.md](doc/ROADMAP.md) | Implementation phases |
| [doc/adr/](doc/adr/) | Architecture decision records |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Contributing & development

```bash
dart pub get
dart analyze
dart test
dart run tool/verify.dart   # quick (CI) or: full
```

Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before opening pull requests or reporting vulnerabilities.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgments

- The threshold cryptography and distributed key-generation research community
- The Dart & Flutter ecosystems
- Companion packages: `pqcrypto`, `pqforge`

---

**pqthreshold** — because some keys should never exist in only one place.
