/// C3 threshold signing ceremony helpers (`doc/API.md` §4.4).
library;

import 'dart:typed_data';

import '../errors/threshold_exception.dart';
import '../sharing/share.dart';
import '../signing/partial_signature.dart';
import '../signing/threshold_signer.dart';

/// Orchestration for FROST threshold signing (C3).
abstract final class ThresholdSigningCeremony {
  /// In-process C3 simulation — prefer `package:pqthreshold/testing.dart`.
  static Future<Uint8List> simulate({
    required List<Share> shares,
    required Uint8List message,
    Uint8List? context,
  }) async {
    assertShareSetConsistent(shares);
    final params = shares.first.params;
    if (shares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} shares, got ${shares.length}',
      );
    }

    final publicKey = PublicKey.create(
      params: params,
      ceremonyId: shares.first.ceremonyId,
      publicKeyBytes: shares.first.verificationData,
    );

    final partials = <PartialSignature>[];
    for (final share in shares.take(params.t)) {
      partials.add(
        await ThresholdSigner.signPartial(
          share: share,
          message: message,
          context: context,
        ),
      );
    }

    return ThresholdSigner.combine(
      partials: partials,
      publicKey: publicKey,
      message: message,
      context: context,
    );
  }
}
