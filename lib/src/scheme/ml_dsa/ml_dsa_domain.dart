/// ML-DSA threshold domain separation (`doc/ML_DSA_THRESHOLD_PROFILE.md` §4).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../../params/threshold_params.dart';
import '../../util/ceremony_id.dart';
import '../../params/scheme_id.dart';
import '../dkg/dkg_crypto.dart' show computeRosterHash;

/// Builds the ML-DSA threshold ceremony identifier string bytes.
Uint8List mlDsaThresholdIdentifier({
  required Uint8List ceremonyId,
  required ThresholdParams params,
}) {
  validateCeremonyId(ceremonyId);
  final rosterHash = computeRosterHash(params.n);
  return PqBytes.concat([
    Uint8List.fromList('pqthreshold-ml-dsa-threshold-v1'.codeUnits),
    Uint8List.fromList([0]),
    ceremonyId,
    _uint16Be(params.t),
    _uint16Be(params.n),
    _uint16Be(params.scheme.wireOrdinal),
    rosterHash,
  ]);
}

/// Message binding for ML-DSA threshold signing sessions.
Uint8List mlDsaMessageBinding({
  required Uint8List ceremonyId,
  required Uint8List jointPublicKey,
  required Uint8List message,
  Uint8List? context,
}) {
  validateCeremonyId(ceremonyId);
  final ctx = context ?? Uint8List(0);
  return PqBytes.sha256(
    PqBytes.concat([
      Uint8List.fromList('pqthreshold/v2/ml-dsa-message-binding'.codeUnits),
      Uint8List.fromList([0]),
      ceremonyId,
      PqBytes.lengthPrefixed([jointPublicKey]),
      PqBytes.lengthPrefixed([message]),
      PqBytes.lengthPrefixed([ctx]),
    ]),
  );
}

Uint8List _uint16Be(int value) {
  final out = Uint8List(2);
  out.buffer.asByteData().setUint16(0, value, Endian.big);
  return out;
}
