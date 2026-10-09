/// C3 ML-DSA threshold signing ceremony (M2 beta).
library;

import 'dart:typed_data';

import '../scheme/ml_dsa/ml_dsa_share.dart';
import '../scheme/ml_dsa/ml_dsa_threshold_signer.dart';

/// Orchestration for ML-DSA threshold signing (C3 beta).
abstract final class MlDsaThresholdSigningCeremony {
  /// In-process C3 via Mithril bridge — Tier 2 tests and examples.
  static Future<Uint8List> simulate({
    required List<MlDsaShare> shares,
    required Uint8List message,
    Uint8List? context,
    String? mithrilBridgePath,
  }) => MlDsaThresholdSigner.sign(
    shares: shares,
    message: message,
    context: context,
    mithrilBridgePath: mithrilBridgePath,
  );
}
