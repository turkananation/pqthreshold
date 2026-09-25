/// C5 rotation ceremony helpers (`doc/API.md` §4.4).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../dkg/dkg_simulator.dart';
import '../errors/threshold_exception.dart';
import '../sharing/share.dart';
import '../signing/partial_signature.dart';
import '../signing/threshold_signer.dart';
import '../transcript/transcript.dart';
import '../util/ceremony_id.dart';
import 'continuity_payload.dart';
import 'continuity_proof.dart';

/// Orchestration for threshold key rotation with continuity evidence (C5).
abstract final class RotationCeremony {
  /// In-process C5 simulation — prefer `package:pqthreshold/testing.dart`.
  static Future<
      ({
        List<Share> newShares,
        PublicKey newPublicKey,
        ContinuityProof continuityProof,
        Transcript newTranscript,
      })> simulate({
    required List<Share> oldShares,
    required PublicKey oldPublicKey,
    Uint8List? newCeremonyId,
    int? signedAtUnixSeconds,
  }) async {
    assertShareSetConsistent(oldShares);
    if (!PqBytes.constantTimeEquals(
      oldShares.first.ceremonyId,
      oldPublicKey.ceremonyId,
    )) {
      throw WrongCeremony('oldShares ceremonyId does not match oldPublicKey');
    }
    for (final share in oldShares) {
      if (!PqBytes.constantTimeEquals(
        share.verificationData,
        oldPublicKey.bytes,
      )) {
        throw InconsistentShares(
          'Share verificationData does not match oldPublicKey',
        );
      }
    }

    final params = oldPublicKey.params;
    if (oldShares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} old shares for continuity signing',
      );
    }

    final newCeremony = newCeremonyId ?? generateCeremonyId();
    validateCeremonyId(newCeremony);
    final signedAt = signedAtUnixSeconds ?? 1_700_000_000;

    final dkg = DkgSimulator.run(
      params: params,
      ceremonyId: newCeremony,
      participantIds: [for (final s in oldShares) s.participantId],
    );

    final payload = buildContinuityPayload(
      oldPublicKeyBytes: oldPublicKey.bytes,
      newPublicKeyBytes: dkg.publicKey.bytes,
      signedAtUnixSeconds: signedAt,
      oldCeremonyId: oldPublicKey.ceremonyId,
      newCeremonyId: newCeremony,
    );

    final partials = <PartialSignature>[];
    for (final share in oldShares.take(params.t)) {
      partials.add(
        await ThresholdSigner.signPartial(
          share: share,
          message: payload,
        ),
      );
    }

    final signature = ThresholdSigner.combine(
      partials: partials,
      publicKey: oldPublicKey,
      message: payload,
    );

    final proof = ContinuityProof.create(
      oldCeremonyId: oldPublicKey.ceremonyId,
      newCeremonyId: newCeremony,
      oldPublicKeyBytes: oldPublicKey.bytes,
      newPublicKeyBytes: dkg.publicKey.bytes,
      signedAtUnixSeconds: signedAt,
      thresholdSignature: signature,
    );

    return (
      newShares: dkg.shares,
      newPublicKey: dkg.publicKey,
      continuityProof: proof,
      newTranscript: dkg.transcripts.first,
    );
  }
}
