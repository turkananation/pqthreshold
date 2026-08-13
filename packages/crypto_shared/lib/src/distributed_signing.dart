/// Multi-party C3 without in-process [SigningSimulator].
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

import 'signing_job_coordinator.dart';

/// Runs threshold signing with officers submitting partials to a coordinator.
abstract final class DistributedSigningCoordinator {
  /// Each [shares] entry signs in-process and submits to [coordinator].
  static Future<Uint8List> run({
    required List<Share> shares,
    required Uint8List message,
    SigningJobCoordinator? coordinator,
    Uint8List? context,
  }) async {
    assertShareSetConsistent(shares);
    final params = shares.first.params;
    if (shares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} shares, got ${shares.length}',
      );
    }

    final publicKey = PublicKey.fromShareSet(shares);

    final jobs = coordinator ?? SigningJobCoordinator();
    final jobId = jobs.createJob(
      publicKey: publicKey,
      message: message,
      context: context,
    );

    for (final share in shares.take(params.t)) {
      final partial = await ThresholdSigner.signPartial(
        share: share,
        message: message,
        context: context,
      );
      jobs.submitPartial(jobId: jobId, partial: partial);
    }

    final signature = jobs.tryCombine(jobId);
    if (signature == null) {
      throw StateError('Failed to combine ${params.t} partial signatures');
    }
    return signature;
  }
}
