/// C5 continuity signed payload (`doc/PROTOCOL_MESSAGES.md` §6).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../util/ceremony_id.dart';

/// Builds the bytes threshold-signed under the **old** joint key.
Uint8List buildContinuityPayload({
  required Uint8List oldPublicKeyBytes,
  required Uint8List newPublicKeyBytes,
  required int signedAtUnixSeconds,
  required Uint8List oldCeremonyId,
  required Uint8List newCeremonyId,
}) {
  validateCeremonyId(oldCeremonyId);
  validateCeremonyId(newCeremonyId);
  if (oldPublicKeyBytes.length != 32 || newPublicKeyBytes.length != 32) {
    throw ArgumentError('Public keys must be 32-byte Ed25519 encodings');
  }
  RangeError.checkNotNegative(signedAtUnixSeconds, 'signedAtUnixSeconds');
  return PqBytes.concat([
    PqBytes.utf8Bytes('pqthreshold-continuity-v1'),
    Uint8List.fromList([0x00]),
    oldPublicKeyBytes,
    newPublicKeyBytes,
    PqBytes.uint64(signedAtUnixSeconds),
    oldCeremonyId,
    newCeremonyId,
  ]);
}
