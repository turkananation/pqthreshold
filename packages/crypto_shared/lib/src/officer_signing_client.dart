/// One officer's C3 partial signature submission via coordinator relay.
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

import 'signing_job_coordinator.dart';

/// Officer-side C3 helper when partials are collected by a coordinator service.
final class OfficerSigningClient {
  OfficerSigningClient({required this.share, required this.coordinator});

  final Share share;
  final SigningJobCoordinator coordinator;

  /// Signs [message] and submits partial to [jobId].
  Future<PartialSignature> signAndSubmit({
    required String jobId,
    required Uint8List message,
    Uint8List? context,
  }) async {
    final partial = await ThresholdSigner.signPartial(
      share: share,
      message: message,
      context: context,
    );
    coordinator.submitPartial(jobId: jobId, partial: partial);
    return partial;
  }
}
