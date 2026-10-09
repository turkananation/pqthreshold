/// C2 dealer-based sharing ceremony helpers (`doc/CEREMONIES.md` §6).
library;

import 'dart:typed_data';

import '../params/threshold_params.dart';
import '../scheme/feldman/feldman_vss.dart';
import '../sharing/share.dart';
import '../sharing/verifiable_secret_sharing.dart';
import '../util/ceremony_id.dart';

/// Orchestration for dealer-based VSS (C2).
abstract final class DealerCeremony {
  /// Tier 1: splits [secret] into [params.n] verifiable shares.
  static ({
    List<Share> shares,
    PublicKey publicKey,
    List<Uint8List> verificationData,
  })
  split({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required Uint8List secret,
    List<String>? participantIds,
  }) {
    validateCeremonyId(ceremonyId);
    final outcome = VerifiableSecretSharing.split(
      params: params,
      ceremonyId: ceremonyId,
      secret: secret,
      participantIds: participantIds,
    );
    return (
      shares: outcome.shares,
      publicKey: outcome.publicKey,
      verificationData: outcome.verificationData,
    );
  }

  /// Verifies one share against Feldman [verificationData] (commitment vector).
  static void verifyShare({
    required Share share,
    required List<Uint8List> verificationData,
  }) {
    VerifiableSecretSharing.verifyShare(
      share: share,
      verificationData: verificationData,
    );
  }

  /// Verifies [share] against encoded Feldman commitment [commitmentsBlob].
  static void verifyShareFromBlob({
    required Share share,
    required Uint8List commitmentsBlob,
  }) {
    verifyShare(
      share: share,
      verificationData: FeldmanVss.decodeCommitments(commitmentsBlob),
    );
  }
}
