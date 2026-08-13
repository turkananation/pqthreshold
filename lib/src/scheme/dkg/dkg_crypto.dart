/// Gennaro DKG cryptographic helpers (`doc/FROST_PROFILE.md` §6.3).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../params/threshold_params.dart';
import '../feldman/ed25519_curve_ops.dart';
import '../feldman/ed25519_scalar.dart';
import '../feldman/feldman_vss.dart';

/// Domain-separated DKG identifier bytes.
@internal
Uint8List buildDkgIdentifier({
  required Uint8List ceremonyId,
  required ThresholdParams params,
}) {
  return PqBytes.concat([
    Uint8List.fromList('pqthreshold-dkg-ed25519-v1'.codeUnits),
    Uint8List.fromList([0x00]),
    ceremonyId,
    _uint16Be(params.t),
    _uint16Be(params.n),
    computeRosterHash(params.n),
  ]);
}

/// Roster hash for indices `1..n` (`doc/FROST_PROFILE.md` §5).
Uint8List computeRosterHash(int n) {
  final indices = BytesBuilder(copy: false);
  for (var i = 1; i <= n; i++) {
    indices.add(_uint16Be(i));
  }
  return PqBytes.sha256(PqBytes.lengthPrefixed([indices.toBytes()]));
}

/// Joint public key = sum of all participants' constant-term commitments.
Uint8List computeJointPublicKey(List<List<Uint8List>> allCommitments) {
  if (allCommitments.isEmpty) {
    throw ArgumentError('No commitment sets provided');
  }
  var pk = allCommitments.first.first;
  for (var i = 1; i < allCommitments.length; i++) {
    pk = Ed25519CurveOps.pointAdd(pk, allCommitments[i].first);
  }
  return pk;
}

/// Final secret share = sum of received share scalars mod **L**.
BigInt combineShareScalars(List<Uint8List> shareScalarsLe) {
  var sum = BigInt.zero;
  for (final bytes in shareScalarsLe) {
    sum = scalarAdd(sum, scalarFromLeBytes(bytes));
  }
  return sum;
}

/// Validates a Round2 share against sender Round1 commitments.
void verifyDkgShare({
  required int recipientIndex,
  required Uint8List shareScalarLe,
  required List<Uint8List> senderCommitments,
}) {
  FeldmanVss.verifyShareEquation(
    shareIndex: recipientIndex,
    shareScalarLe: shareScalarLe,
    commitments: senderCommitments,
  );
}

Uint8List _uint16Be(int value) {
  final out = Uint8List(2);
  out.buffer.asByteData().setUint16(0, value, Endian.big);
  return out;
}
