/// Tier 2 in-process ceremony simulation (`doc/API.md` §2).
library;

import 'dart:typed_data';

import 'src/ceremony/continuity_proof.dart';
import 'src/ceremony/rotation_ceremony.dart';
import 'src/ceremony/threshold_signing_ceremony.dart';
import 'src/sharing/share.dart';
import 'src/transcript/transcript.dart';

export 'src/ceremony/continuity_proof.dart' show ContinuityProof;
export 'src/ceremony/rotation_ceremony.dart' show RotationCeremony;
export 'src/ceremony/threshold_signing_ceremony.dart'
    show ThresholdSigningCeremony;
export 'src/dkg/dkg_simulator.dart' show DkgSimulator;
export 'src/sharing/share.dart' show PublicKey, Share;
export 'src/transcript/transcript.dart' show Transcript;

/// Runs C5 rotation in one process — tests, examples, and docs only.
abstract final class RotationSimulator {
  /// Delegates to [RotationCeremony.simulate].
  static Future<
      ({
        List<Share> newShares,
        PublicKey newPublicKey,
        ContinuityProof continuityProof,
        Transcript newTranscript,
      })> run({
    required List<Share> oldShares,
    required PublicKey oldPublicKey,
    Uint8List? newCeremonyId,
    int? signedAtUnixSeconds,
  }) =>
      RotationCeremony.simulate(
        oldShares: oldShares,
        oldPublicKey: oldPublicKey,
        newCeremonyId: newCeremonyId,
        signedAtUnixSeconds: signedAtUnixSeconds,
      );
}

/// Runs C3 signing in one process — tests, examples, and docs only.
abstract final class SigningSimulator {
  /// Delegates to [ThresholdSigningCeremony.simulate].
  static Future<Uint8List> run({
    required List<Share> shares,
    required Uint8List message,
    Uint8List? context,
  }) =>
      ThresholdSigningCeremony.simulate(
        shares: shares,
        message: message,
        context: context,
      );
}
