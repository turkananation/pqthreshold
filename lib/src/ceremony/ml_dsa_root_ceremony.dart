/// C1 ML-DSA threshold root ceremony (M2 beta).
library;

import 'dart:typed_data';

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import '../params/threshold_params.dart';
import '../util/ceremony_id.dart';
import '../scheme/ml_dsa/mithril_bridge.dart';
import '../scheme/ml_dsa/ml_dsa_share.dart';

/// Orchestration for ML-DSA threshold root generation (C1 beta).
abstract final class MlDsaRootCeremony {
  /// In-process C1 simulation via Mithril RSS keygen (Tier 2).
  ///
  /// Returns simulated [MlDsaShare] values that reference a shared ceremony
  /// seed — suitable for tests until distributed lattice DKG ships.
  static Future<
      ({
        List<MlDsaShare> shares,
        MlDsaPublicKey publicKey,
      })> simulate(
    ThresholdParams params, {
    Uint8List? ceremonyId,
    List<String>? participantIds,
    String? mithrilBridgePath,
  }) async {
    if (params.scheme != SchemeId.mlDsa44ThresholdV1) {
      throw SchemeNotImplemented(
        'M2 Mithril bridge supports mlDsa44ThresholdV1 only; got ${params.scheme}',
      );
    }
    final cid = ceremonyId ?? generateCeremonyId();
    final ids = participantIds ??
        [for (var i = 1; i <= params.n; i++) 'officer$i'];

    final keygen = await mithrilKeygen(
      t: params.t,
      n: params.n,
      executablePath: mithrilBridgePath,
    );

    final publicKey = MlDsaPublicKey.create(
      params: params,
      ceremonyId: cid,
      publicKeyBytes: keygen.publicKey,
    );

    final shares = <MlDsaShare>[];
    for (var i = 0; i < params.n; i++) {
      shares.add(
        MlDsaShare.simulate(
          params: params,
          ceremonyId: cid,
          participantId: ids[i],
          index: i + 1,
          ceremonySeed: keygen.ceremonySeed,
        ),
      );
    }

    return (shares: shares, publicKey: publicKey);
  }
}
