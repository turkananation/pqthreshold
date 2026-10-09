/// ML-DSA threshold signing API (M2 beta — Mithril bridge, ML-DSA-44).
library;

import 'dart:typed_data';

import '../../errors/threshold_exception.dart';
import '../../params/scheme_id.dart';
import '../../params/threshold_params.dart';
import 'ml_dsa_share.dart';
import 'ml_dsa_signing_message.dart';
import 'ml_dsa_threshold_verifier.dart';
import 'mithril_bridge.dart';

/// Threshold ML-DSA signing (C3) — M2 beta via Mithril bridge.
abstract final class MlDsaThresholdSigner {
  /// Threshold-sign [message] with ≥ [params.t] shares from [shares].
  ///
  /// M2 beta: uses in-process Mithril coordinator (honest combine model).
  /// Requires `mithril_bridge` binary and **ML-DSA-44** scheme
  /// (`mlDsa44ThresholdV1`) until native ML-DSA-65 lands.
  static Future<Uint8List> sign({
    required List<MlDsaShare> shares,
    required Uint8List message,
    Uint8List? context,
    String? mithrilBridgePath,
  }) async {
    assertMlDsaShareSetConsistent(shares);
    final params = shares.first.params;
    if (params.scheme != SchemeId.mlDsa44ThresholdV1) {
      throw SchemeNotImplemented(
        'M2 Mithril bridge supports mlDsa44ThresholdV1 only; got ${params.scheme}',
      );
    }
    if (shares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} shares, got ${shares.length}',
      );
    }

    final publicKey = MlDsaPublicKey.create(
      params: params,
      ceremonyId: shares.first.ceremonyId,
      publicKeyBytes: await _derivePublicKey(
        params: params,
        ceremonySeed: shares.first.ceremonySeedBytes(),
        mithrilBridgePath: mithrilBridgePath,
      ),
    );

    final active = shares.take(params.t).map((s) => s.mithrilPartyId).toList()
      ..sort();

    final signature = await mithrilThresholdSign(
      t: params.t,
      n: params.n,
      ceremonySeed: shares.first.ceremonySeedBytes(),
      activePartyIdsZeroBased: active,
      message: message,
      executablePath: mithrilBridgePath,
    );

    if (!MlDsaThresholdVerifier.verify(
      scheme: params.scheme,
      publicKey: publicKey.bytes,
      message: message,
      signature: signature,
      context: context,
    )) {
      throw InvalidPartialSignature(
        'Mithril produced invalid ML-DSA signature',
      );
    }
    return signature;
  }

  /// Threshold-sign and export Mithril wire round payloads (M3 beta).
  ///
  /// Returns the combined signature plus canonical [MlDsaSigningMessage] values
  /// for dir-transport under `round1/`, `round2/`, `round3/`.
  static Future<
    ({
      Uint8List signature,
      Uint8List sessionId,
      List<MlDsaSigningMessage> wireMessages,
    })
  >
  signWithWire({
    required List<MlDsaShare> shares,
    required Uint8List message,
    Uint8List? context,
    String? mithrilBridgePath,
  }) async {
    assertMlDsaShareSetConsistent(shares);
    final params = shares.first.params;
    if (params.scheme != SchemeId.mlDsa44ThresholdV1) {
      throw SchemeNotImplemented(
        'M2 Mithril bridge supports mlDsa44ThresholdV1 only; got ${params.scheme}',
      );
    }
    if (shares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} shares, got ${shares.length}',
      );
    }

    final publicKeyBytes = await _derivePublicKey(
      params: params,
      ceremonySeed: shares.first.ceremonySeedBytes(),
      mithrilBridgePath: mithrilBridgePath,
    );
    final publicKey = MlDsaPublicKey.create(
      params: params,
      ceremonyId: shares.first.ceremonyId,
      publicKeyBytes: publicKeyBytes,
    );

    final active = shares.take(params.t).map((s) => s.mithrilPartyId).toList()
      ..sort();

    final wire = await mithrilWireSign(
      t: params.t,
      n: params.n,
      ceremonySeed: shares.first.ceremonySeedBytes(),
      activePartyIdsZeroBased: active,
      message: message,
      executablePath: mithrilBridgePath,
    );

    if (!MlDsaThresholdVerifier.verify(
      scheme: params.scheme,
      publicKey: publicKey.bytes,
      message: message,
      signature: wire.signature,
      context: context,
    )) {
      throw InvalidPartialSignature(
        'Mithril wire_sign produced invalid signature',
      );
    }

    final wireMessages = mlDsaMessagesFromWireSignJson(
      params: params,
      ceremonyId: shares.first.ceremonyId,
      sessionId: wire.sessionId,
      wireJson: wire.wireJson,
    );

    return (
      signature: wire.signature,
      sessionId: wire.sessionId,
      wireMessages: wireMessages,
    );
  }

  static Future<Uint8List> _derivePublicKey({
    required ThresholdParams params,
    required Uint8List ceremonySeed,
    String? mithrilBridgePath,
  }) async {
    final outcome = await mithrilKeygen(
      t: params.t,
      n: params.n,
      seed: ceremonySeed,
      executablePath: mithrilBridgePath,
    );
    return outcome.publicKey;
  }
}
