/// FROST Ed25519 signing core (`doc/FROST_PROFILE.md` §7, draft-irtf-cfrg-frost-15).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../feldman/ed25519_curve_ops.dart';
import '../feldman/ed25519_scalar.dart';
import 'frost_hash.dart';

/// Round-one commitment pair for participant [index].
final class FrostCommitment {
  const FrostCommitment({
    required this.index,
    required this.hiding,
    required this.binding,
  });

  /// 1-based signer index.
  final int index;

  /// Hiding nonce commitment **R_i**.
  final Uint8List hiding;

  /// Binding nonce commitment **D_i**.
  final Uint8List binding;
}

/// Ephemeral nonce pair — wipe after use.
@internal
final class FrostNonces {
  FrostNonces({required this.hiding, required this.binding});

  final BigInt hiding;
  final BigInt binding;
}

/// Internal FROST protocol engine for Ed25519.
abstract final class FrostSigning {
  /// Generates hiding/binding nonces using H3 hedging.
  static FrostNonces generateNonces({
    required Uint8List frostIdentifier,
    required BigInt secretShare,
  }) {
    final secretEnc = scalarToLeBytes(secretShare);
    final hidingRandom = PqBytes.randomBytes(32);
    final bindingRandom = PqBytes.randomBytes(32);
    return FrostNonces(
      hiding: frostH3(
        frostIdentifier,
        PqBytes.concat([hidingRandom, secretEnc]),
      ),
      binding: frostH3(
        frostIdentifier,
        PqBytes.concat([bindingRandom, secretEnc]),
      ),
    );
  }

  /// Round-one commitments for [nonces].
  static FrostCommitment commitmentsFromNonces({
    required int index,
    required FrostNonces nonces,
  }) {
    return FrostCommitment(
      index: index,
      hiding: Ed25519CurveOps.scalarBaseMult(scalarToLeBytes(nonces.hiding)),
      binding: Ed25519CurveOps.scalarBaseMult(scalarToLeBytes(nonces.binding)),
    );
  }

  /// Sorted commitment list encoding for H5.
  static Uint8List encodeCommitmentList(List<FrostCommitment> commitments) {
    final sorted = [...commitments]..sort((a, b) => a.index.compareTo(b.index));
    final chunks = <Uint8List>[];
    for (final entry in sorted) {
      chunks.add(serializeParticipantIndex(entry.index));
      chunks.add(entry.hiding);
      chunks.add(entry.binding);
    }
    return PqBytes.concat(chunks);
  }

  /// Binding factor **ρ_i** for each signer in [commitments].
  static Map<int, BigInt> computeBindingFactors({
    required Uint8List frostIdentifier,
    required Uint8List groupPublicKey,
    required Uint8List message,
    required List<FrostCommitment> commitments,
  }) {
    final msgHash = frostH4(frostIdentifier, message);
    final commHash = frostH5(
      frostIdentifier,
      encodeCommitmentList(commitments),
    );
    final prefix = PqBytes.concat([groupPublicKey, msgHash, commHash]);
    final factors = <int, BigInt>{};
    for (final entry in commitments) {
      final rhoInput = PqBytes.concat([
        prefix,
        serializeParticipantIndex(entry.index),
      ]);
      factors[entry.index] = frostH1(frostIdentifier, rhoInput);
    }
    return factors;
  }

  /// Group commitment **R** (draft §4.5).
  static Uint8List computeGroupCommitment({
    required List<FrostCommitment> commitments,
    required Map<int, BigInt> bindingFactors,
  }) {
    final sorted = [...commitments]..sort((a, b) => a.index.compareTo(b.index));
    Uint8List? acc;
    for (final entry in sorted) {
      final rho = bindingFactors[entry.index]!;
      final bindingScaled = Ed25519CurveOps.scalarMult(
        scalarToLeBytes(rho),
        entry.binding,
      );
      final term = Ed25519CurveOps.pointAdd(entry.hiding, bindingScaled);
      acc = acc == null ? term : Ed25519CurveOps.pointAdd(acc, term);
    }
    if (acc == null) {
      throw ArgumentError('commitments must not be empty');
    }
    return acc;
  }

  /// Per-message challenge **c**.
  static BigInt computeChallenge({
    required Uint8List frostIdentifier,
    required Uint8List groupCommitment,
    required Uint8List groupPublicKey,
    required Uint8List message,
  }) {
    final input = PqBytes.concat([groupCommitment, groupPublicKey, message]);
    return frostH2Challenge(input);
  }

  /// Round-two signature share **z_i**.
  static BigInt computeSignatureShare({
    required int signerIndex,
    required BigInt secretShare,
    required FrostNonces nonces,
    required BigInt bindingFactor,
    required BigInt challenge,
    required List<int> signerIndices,
  }) {
    final lambda = lagrangeCoefficientAtZero(signerIndex, signerIndices);
    final term = (lambda * secretShare * challenge) % ed25519SubgroupOrder;
    return (nonces.hiding + (nonces.binding * bindingFactor) + term) %
        ed25519SubgroupOrder;
  }

  /// Aggregates signature shares into RFC 8032 **R||S**.
  static Uint8List aggregateSignature({
    required Uint8List groupCommitment,
    required List<BigInt> signatureShares,
  }) {
    var z = BigInt.zero;
    for (final share in signatureShares) {
      z = (z + share) % ed25519SubgroupOrder;
    }
    return PqBytes.concat([groupCommitment, scalarToLeBytes(z)]);
  }

  /// Validates **z_i** against Round1 commitments (draft §5.3).
  static bool verifySignatureShare({
    required int signerIndex,
    required Uint8List sharePublicKey,
    required FrostCommitment commitment,
    required BigInt signatureShare,
    required Map<int, BigInt> bindingFactors,
    required BigInt challenge,
    required List<int> signerIndices,
  }) {
    final lambda = lagrangeCoefficientAtZero(signerIndex, signerIndices);
    final rho = bindingFactors[signerIndex];
    if (rho == null) return false;

    final lhs = Ed25519CurveOps.scalarBaseMult(scalarToLeBytes(signatureShare));
    final bindingScaled = Ed25519CurveOps.scalarMult(
      scalarToLeBytes(rho),
      commitment.binding,
    );
    var rhs = Ed25519CurveOps.pointAdd(commitment.hiding, bindingScaled);
    final pkTerm = Ed25519CurveOps.scalarMult(
      scalarToLeBytes((lambda * challenge) % ed25519SubgroupOrder),
      sharePublicKey,
    );
    rhs = Ed25519CurveOps.pointAdd(rhs, pkTerm);
    return PqBytes.constantTimeEquals(lhs, rhs);
  }
}
