/// Experimental post-quantum threshold test and simulation helpers.
///
/// These helpers are not part of the stable FROST Ed25519 1.0 contract.
library;

import 'dart:typed_data';

import 'src/ceremony/ml_dsa_root_ceremony.dart';
import 'src/ceremony/ml_dsa_threshold_signing_ceremony.dart';
import 'src/params/threshold_params.dart';

export 'testing.dart';

/// Runs ML-DSA threshold C1+C3 in one process (M2 beta — requires Mithril).
abstract final class MlDsaThresholdSimulator {
  /// Full C1 → C3 simulation for ML-DSA-44.
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
