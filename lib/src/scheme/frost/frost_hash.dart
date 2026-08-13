/// FROST profile hash functions H1–H5 (`doc/FROST_PROFILE.md` §5).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../feldman/ed25519_scalar.dart';

/// H1: binding-factor scalars.
BigInt frostH1(Uint8List frostIdentifier, Uint8List input) {
  return _hashToScalar(_sha512(PqBytes.concat([frostIdentifier, input])));
}

/// H2: per-message challenge scalar.
///
/// Uses RFC 8032 / FROST-Ed25519 challenge shape (no [frostIdentifier]
/// prefix) so [ThresholdSigner.verify] succeeds via pqforge Ed25519 verify.
BigInt frostH2Challenge(Uint8List challengeInput) {
  return _hashToScalar(_sha512(challengeInput));
}

/// Profile H2 with domain tag — used where draft allows prefixed hashes.
BigInt frostH2(Uint8List frostIdentifier, Uint8List input) {
  return _hashToScalar(
    _sha512(
      PqBytes.concat([frostIdentifier, Uint8List.fromList([0x02]), input]),
    ),
  );
}

/// H3: nonce derivation scalar.
BigInt frostH3(Uint8List frostIdentifier, Uint8List input) {
  return _hashToScalar(
    _sha512(
      PqBytes.concat([frostIdentifier, Uint8List.fromList([0x03]), input]),
    ),
  );
}

/// H4: fixed-length message digest for binding-factor prefix.
Uint8List frostH4(Uint8List frostIdentifier, Uint8List message) {
  return _sha512(
    PqBytes.concat([frostIdentifier, Uint8List.fromList([0x04]), message]),
  );
}

/// H5: fixed-length commitment-list digest for binding-factor prefix.
Uint8List frostH5(Uint8List frostIdentifier, Uint8List encodedCommitments) {
  return _sha512(
    PqBytes.concat([
      frostIdentifier,
      Uint8List.fromList([0x05]),
      encodedCommitments,
    ]),
  );
}

BigInt _hashToScalar(Uint8List digest) {
  return scalarFromLeBytes(digest);
}

Uint8List _sha512(Uint8List input) => PqBytes.sha512(input);

/// Encodes participant [index] as a 32-byte canonical scalar.
Uint8List serializeParticipantIndex(int index) {
  if (index < 1 || index > 0xFFFF) {
    throw ArgumentError('participant index out of range');
  }
  return scalarToLeBytes(BigInt.from(index));
}
