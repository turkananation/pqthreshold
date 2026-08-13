/// FROST profile identifiers and message binding (`doc/FROST_PROFILE.md` §5).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;

import '../../params/threshold_params.dart';
import '../../sharing/share.dart';
import '../dkg/dkg_crypto.dart';

/// Builds the FROST transcript identifier for [params] and [ceremonyId].
Uint8List buildFrostIdentifier({
  required Uint8List ceremonyId,
  required ThresholdParams params,
}) {
  return PqBytes.concat([
    Uint8List.fromList('pqthreshold-frost-ed25519-v1'.codeUnits),
    Uint8List.fromList([0x00]),
    ceremonyId,
    _uint16Be(params.t),
    _uint16Be(params.n),
    computeRosterHash(params.n),
  ]);
}

/// Application message binding (`doc/SERIALIZATION.md` §5).
Uint8List computeMessageBinding({
  required Uint8List ceremonyId,
  required Uint8List publicKeyBytes,
  required Uint8List message,
  Uint8List? context,
}) {
  final ctx = context ?? Uint8List(0);
  return PqBytes.sha256(
    PqBytes.concat([
      Uint8List.fromList('pqthreshold/v1/message-binding'.codeUnits),
      Uint8List.fromList([0x00]),
      ceremonyId,
      publicKeyBytes,
      PqBytes.lengthPrefixed([message]),
      PqBytes.lengthPrefixed([ctx]),
    ]),
  );
}

/// Convenience binding from a [PublicKey] and [message].
Uint8List messageBindingFor({
  required PublicKey publicKey,
  required Uint8List message,
  Uint8List? context,
}) {
  return computeMessageBinding(
    ceremonyId: publicKey.ceremonyId,
    publicKeyBytes: publicKey.bytes,
    message: message,
    context: context,
  );
}

Uint8List _uint16Be(int value) {
  final out = Uint8List(2);
  out.buffer.asByteData().setUint16(0, value, Endian.big);
  return out;
}
