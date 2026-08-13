/// Feldman verifiable secret sharing over Ed25519 (`doc/FROST_PROFILE.md` §6).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import 'ed25519_curve_ops.dart';
import 'ed25519_scalar.dart';

/// Feldman commitment vector and verification helpers.
@internal
abstract final class FeldmanVss {
  static const int scalarBytes = 32;
  static const int pointBytes = 32;

  /// Builds Feldman commitments `C_k = a_k * B` for polynomial coefficients.
  static List<Uint8List> commitmentsFromCoefficients(List<BigInt> coefficients) {
    return [
      for (final coeff in coefficients)
        Ed25519CurveOps.scalarBaseMult(scalarToLeBytes(coeff)),
    ];
  }

  /// Serializes [commitments] as `uint8(t) || 32*t` bytes.
  static Uint8List encodeCommitments(List<Uint8List> commitments) {
    if (commitments.isEmpty || commitments.length > 255) {
      throw InvalidParams('Invalid commitment count: ${commitments.length}');
    }
    final out = BytesBuilder(copy: false);
    out.addByte(commitments.length);
    for (final c in commitments) {
      if (c.length != pointBytes) {
        throw InvalidParams('Commitment must be $pointBytes bytes');
      }
      out.add(c);
    }
    return out.toBytes();
  }

  /// Parses commitments from [bytes].
  static List<Uint8List> decodeCommitments(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw SerializationError('Empty Feldman commitment blob');
    }
    final count = bytes[0];
    final expected = 1 + count * pointBytes;
    if (bytes.length != expected) {
      throw SerializationError(
        'Invalid Feldman commitment length: expected $expected, got ${bytes.length}',
      );
    }
    return [
      for (var i = 0; i < count; i++)
        Uint8List.sublistView(bytes, 1 + i * pointBytes, 1 + (i + 1) * pointBytes),
    ];
  }

  /// Verifies `shareScalar * B == sum(i^k * C_k)`.
  static void verifyShareEquation({
    required int shareIndex,
    required Uint8List shareScalarLe,
    required List<Uint8List> commitments,
  }) {
    final left = Ed25519CurveOps.scalarBaseMult(shareScalarLe);
    final scalars = <Uint8List>[];
    final x = participantIndexAsScalar(shareIndex);
    var xPow = BigInt.one;
    for (final _ in commitments) {
      scalars.add(scalarToLeBytes(xPow));
      xPow = (xPow * x) % ed25519SubgroupOrder;
    }
    final right = Ed25519CurveOps.multiScalarMult(commitments, scalars);
    if (!PqBytes.constantTimeEquals(left, right)) {
      throw InconsistentShares('Feldman share verification failed for index $shareIndex');
    }
  }

  /// Random polynomial coefficients with [secret] as constant term.
  static List<BigInt> randomPolynomial({
    required BigInt secret,
    required int degree,
  }) {
    if (degree < 0) {
      throw ArgumentError('degree must be >= 0');
    }
    final coeffs = <BigInt>[secret % ed25519SubgroupOrder];
    for (var i = 1; i <= degree; i++) {
      coeffs.add(scalarFromLeBytes(PqBytes.randomBytes(scalarBytes)));
    }
    return coeffs;
  }
}
