/// Public Feldman VSS API (`doc/API.md` §4.2).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' show PqBytes;

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../scheme/feldman/ed25519_scalar.dart';
import '../scheme/feldman/feldman_vss.dart';
import '../util/ceremony_id.dart';
import 'share.dart';

/// Dealer-based verifiable secret sharing (C2).
abstract final class VerifiableSecretSharing {
  /// Dealer splits [secret] into [params.n] verifiable shares.
  static ({
    List<Share> shares,
    List<Uint8List> verificationData,
    PublicKey publicKey,
  })
  split({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required Uint8List secret,
    Iterable<String>? participantIds,
  }) {
    validateCeremonyId(ceremonyId);
    if (secret.length != FeldmanVss.scalarBytes) {
      throw InvalidParams('Secret must be ${FeldmanVss.scalarBytes} bytes');
    }
    final secretScalar = scalarFromLeBytes(secret);
    final coeffs = FeldmanVss.randomPolynomial(
      secret: secretScalar,
      degree: params.t - 1,
    );
    final commitments = FeldmanVss.commitmentsFromCoefficients(coeffs);
    final verificationBlob = FeldmanVss.encodeCommitments(commitments);
    final jointPublicKey = commitments.first;

    final ids = participantIds?.toList(growable: false);
    if (ids != null && ids.length != params.n) {
      throw InvalidParams('participantIds length must equal n=${params.n}');
    }

    final shares = <Share>[];
    for (var i = 1; i <= params.n; i++) {
      final shareScalar = evaluatePolynomialAtIndex(coeffs, i);
      final shareBytes = scalarToLeBytes(shareScalar);
      FeldmanVss.verifyShareEquation(
        shareIndex: i,
        shareScalarLe: shareBytes,
        commitments: commitments,
      );
      shares.add(
        Share.create(
          params: params,
          ceremonyId: ceremonyId,
          participantId: ids == null ? 'participant-$i' : ids[i - 1],
          index: i,
          secretShare: shareBytes,
          verificationData: verificationBlob,
        ),
      );
    }

    final publicKey = PublicKey.create(
      params: params,
      ceremonyId: ceremonyId,
      publicKeyBytes: jointPublicKey,
    );

    return (
      shares: shares,
      verificationData: commitments,
      publicKey: publicKey,
    );
  }

  /// Recipient verifies [share] against Feldman [verificationData].
  static void verifyShare({
    required Share share,
    required List<Uint8List> verificationData,
  }) {
    if (verificationData.length != share.params.t) {
      throw InconsistentShares(
        'Expected ${share.params.t} commitments, got ${verificationData.length}',
      );
    }
    final decoded = FeldmanVss.decodeCommitments(share.verificationData);
    if (!_commitmentsEqual(decoded, verificationData)) {
      throw InconsistentShares(
        'Share verificationData does not match broadcast',
      );
    }
    FeldmanVss.verifyShareEquation(
      shareIndex: share.index,
      shareScalarLe: share.secretShareBytes(),
      commitments: verificationData,
    );
  }

  /// Reconstructs the secret from at least [params.t] [shares].
  static Uint8List reconstruct({required List<Share> shares}) {
    assertShareSetConsistent(shares);
    final params = shares.first.params;
    if (shares.length < params.t) {
      throw InsufficientShares(
        'Need at least ${params.t} shares, got ${shares.length}',
      );
    }
    final selected = shares.take(params.t).toList();
    final indices = selected.map((s) => s.index).toList();
    if (indices.toSet().length != indices.length) {
      throw InconsistentShares('Duplicate share indices in reconstruction set');
    }
    final scalars = selected
        .map((s) => scalarFromLeBytes(s.secretShareBytes()))
        .toList();
    final secret = lagrangeReconstructAtZero(indices, scalars);
    return scalarToLeBytes(secret);
  }

  static bool _commitmentsEqual(List<Uint8List> a, List<Uint8List> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!PqBytes.constantTimeEquals(a[i], b[i])) return false;
    }
    return true;
  }
}
