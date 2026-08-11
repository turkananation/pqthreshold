# pqthreshold

**High-assurance pure-Dart threshold cryptography & distributed key-management primitives**

[![pub package](https://img.shields.io/pub/v/pqthreshold.svg)](https://pub.dev/packages/pqthreshold)
[![likes](https://img.shields.io/pub/likes/pqthreshold)](https://pub.dev/packages/pqthreshold/score)
[![points](https://img.shields.io/pub/points/pqthreshold)](https://pub.dev/packages/pqthreshold/score)
[![license](https://img.shields.io/github/license/turkananation/pqthreshold)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-%5E3.10-0175C2?logo=dart&logoColor=white)](https://dart.dev)

> Zero native dependencies. Verifiable secret sharing, distributed key generation (DKG), threshold signatures, and multi-party ceremony building blocks for organizational roots, enclave recovery, and self-custodial multi-device setups.

**Documentation** · [Website](https://turkananation.github.io/pqthreshold/) · [Wiki](https://github.com/turkananation/pqthreshold/wiki) · [API reference](https://pub.dev/documentation/pqthreshold/latest/) · [Security model](doc/SECURITY.md)

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

```dart
import 'package:pqthreshold/pqthreshold.dart';

Future<void> main() async {
  // Example: 3-of-5 threshold setup (illustrative API shape)
  final params = ThresholdParams.tOfN(t: 3, n: 5);

  // Distributed key generation (no trusted dealer)
  final dkg = await DistributedKeyGeneration.run(params);
  final publicKey = dkg.publicKey;
  final shares = dkg.shares; // one share per participant

  // Later: threshold signing (quorum of shares required)
  final partials = <PartialSignature>[];
  for (final share in shares.take(params.t)) {
    partials.add(await ThresholdSigner.signPartial(share, message));
  }

  final signature = ThresholdSigner.combine(partials, publicKey);
  final valid = ThresholdSigner.verify(publicKey, message, signature);
  print('threshold signature valid: $valid');
}
```

> The exact API surface is versioned and documented in the package.  
> The snippet above shows the intended shape, not a final frozen contract.

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

See [doc/SECURITY.md](doc/SECURITY.md) for the full threat model, assumptions, and claim boundaries.

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
| Verifiable secret sharing | Core target |
| Distributed key generation | Core target |
| Threshold signatures | Core target |
| Ceremony helpers | Core target |
| Pure Dart / zero FFI | Required |
| Web support | Where the algorithms allow |
| Production hardening & vectors | Ongoing |

The package follows the same evidence-oriented style as `pqcrypto`: clear documentation of what is implemented, what is tested, and what is explicitly not claimed.

---

## Installation

```yaml
dependencies:
  pqthreshold: ^0.1.0
```

```bash
dart pub get
# or
flutter pub get
```

---

## Documentation map

| Document | Purpose |
| ---------- | --------- |
| [README.md](README.md) | This file |
| [doc/SECURITY.md](doc/SECURITY.md) | Threat model & claim boundaries |
| [doc/ARCHITECTURE.md](doc/ARCHITECTURE.md) | Internal structure |
| [doc/CEREMONIES.md](doc/CEREMONIES.md) | Recommended multi-party flows |
| [doc/INTEGRATION.md](doc/INTEGRATION.md) | Working with pqcrypto / pqforge |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Contributing & development

```bash
dart pub get
dart analyze
dart test
dart run tool/verify.dart   # if present
```

Please read `CONTRIBUTING.md` and `SECURITY.md` before opening pull requests or reporting vulnerabilities.

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
