/// In-memory C3 signing job coordinator (Serverpod-friendly).
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

/// Collects partial signatures until quorum, then combines.
final class SigningJobCoordinator {
  final _jobs = <String, _SigningJob>{};

  /// Registers a new signing job; returns [jobId].
  String createJob({
    required PublicKey publicKey,
    required Uint8List message,
    Uint8List? context,
  }) {
    final jobId =
        'sign-${_jobs.length + 1}-${DateTime.now().microsecondsSinceEpoch}';
    _jobs[jobId] = _SigningJob(
      publicKey: publicKey,
      message: Uint8List.fromList(message),
      context: context == null ? null : Uint8List.fromList(context),
      t: publicKey.params.t,
    );
    return jobId;
  }

  /// Stores one officer partial (public round material from [PartialSignature.toBytes]).
  void submitPartial({
    required String jobId,
    required PartialSignature partial,
  }) {
    final job = _jobs[jobId];
    if (job == null) {
      throw ArgumentError('Unknown signing job: $jobId');
    }
    job.partials[partial.signerIndex] = partial;
  }

  /// Returns combined signature when ≥ t distinct partials are present.
  Uint8List? tryCombine(String jobId) {
    final job = _jobs[jobId];
    if (job == null) {
      throw ArgumentError('Unknown signing job: $jobId');
    }
    if (job.partials.length < job.t) {
      return null;
    }
    final partials = job.partials.values.take(job.t).toList();
    return ThresholdSigner.combine(
      partials: partials,
      publicKey: job.publicKey,
      message: job.message,
      context: job.context,
    );
  }

  /// Partial count for UI / polling.
  int partialCount(String jobId) => _jobs[jobId]?.partials.length ?? 0;
}

final class _SigningJob {
  _SigningJob({
    required this.publicKey,
    required this.message,
    required this.context,
    required this.t,
  });

  final PublicKey publicKey;
  final Uint8List message;
  final Uint8List? context;
  final int t;
  final partials = <int, PartialSignature>{};
}
