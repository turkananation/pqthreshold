/// Tier 2 in-process ceremony simulation (`doc/API.md` §2).
library;

import 'dart:typed_data';

import 'src/ceremony/ml_dsa_root_ceremony.dart';
import 'src/ceremony/ml_dsa_threshold_signing_ceremony.dart';
import 'src/ceremony/continuity_proof.dart';
import 'src/ceremony/rotation_ceremony.dart';
import 'src/ceremony/threshold_signing_ceremony.dart';
import 'src/params/threshold_params.dart';
import 'src/sharing/share.dart';
import 'src/transcript/transcript.dart';

export 'src/ceremony/continuity_proof.dart' show ContinuityProof;
export 'src/ceremony/ml_dsa_root_ceremony.dart' show MlDsaRootCeremony;
export 'src/ceremony/ml_dsa_threshold_signing_ceremony.dart'
    show MlDsaThresholdSigningCeremony;
export 'src/ceremony/rotation_ceremony.dart' show RotationCeremony;
export 'src/ceremony/threshold_signing_ceremony.dart'
    show ThresholdSigningCeremony;
export 'src/dkg/dkg_simulator.dart' show DkgSimulator;
export 'src/scheme/ml_dsa/ml_dsa_share.dart' show MlDsaPublicKey, MlDsaShare;
export 'src/sharing/share.dart' show PublicKey, Share;
export 'src/transcript/transcript.dart' show Transcript;

/// Runs ML-DSA threshold C1+C3 in one process (M2 beta — requires mithril_bridge).
abstract final class MlDsaThresholdSimulator {
  /// Full C1 → C3 simulate for ML-DSA-44.
  static Future<Uint8List> run({
    required ThresholdParams params,
    required Uint8List message,
    Uint8List? ceremonyId,
    List<String>? participantIds,
    String? mithrilBridgePath,
  }) async {
    final root = await MlDsaRootCeremony.simulate(
      params,
      ceremonyId: ceremonyId,
      participantIds: participantIds,
      mithrilBridgePath: mithrilBridgePath,
    );
    return MlDsaThresholdSigningCeremony.simulate(
      shares: root.shares,
      message: message,
      mithrilBridgePath: mithrilBridgePath,
    );
  }
}

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
