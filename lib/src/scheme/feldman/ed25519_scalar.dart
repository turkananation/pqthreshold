/// Ed25519 scalar field **Z/L** helpers for Shamir sharing.
library;

import 'dart:typed_data';

import 'internal/big_int_bytes.dart';
import 'internal/ed25519_field.dart';

/// Ed25519 subgroup order **L**.
final BigInt ed25519SubgroupOrder = RegisterL.constantL;

/// Reduces [bytes] (little-endian) into **Z/L**.
BigInt scalarFromLeBytes(Uint8List bytes) {
  return bigIntFromBytes(bytes) % ed25519SubgroupOrder;
}

/// Encodes [value] mod **L** as 32-byte little-endian.
Uint8List scalarToLeBytes(BigInt value) {
  final reduced = value % ed25519SubgroupOrder;
  return bigIntToBytes(reduced, Uint8List(32));
}

/// Adds two scalars mod **L**.
BigInt scalarAdd(BigInt a, BigInt b) => (a + b) % ed25519SubgroupOrder;

/// Multiplies two scalars mod **L**.
BigInt scalarMul(BigInt a, BigInt b) => (a * b) % ed25519SubgroupOrder;

/// Computes [base]^ [exponent] mod **L** (Shamir evaluation uses small exponent).
BigInt scalarPowMod(BigInt base, int exponent) {
  var result = BigInt.one;
  var b = base % ed25519SubgroupOrder;
  var e = exponent;
  while (e > 0) {
    if (e.isOdd) {
      result = (result * b) % ed25519SubgroupOrder;
    }
    b = (b * b) % ed25519SubgroupOrder;
    e >>= 1;
  }
  return result;
}

/// Participant index **x** as field element (1..n).
BigInt participantIndexAsScalar(int index) {
  if (index < 1) {
    throw ArgumentError.value(index, 'index', 'must be >= 1');
  }
  return BigInt.from(index) % ed25519SubgroupOrder;
}

/// Lagrange coefficient λ_i(0) for indices in [indices] at evaluation point 0.
BigInt lagrangeCoefficientAtZero(int index, List<int> indices) {
  var numerator = BigInt.one;
  var denominator = BigInt.one;
  final xI = participantIndexAsScalar(index);
  for (final j in indices) {
    if (j == index) continue;
    final xJ = participantIndexAsScalar(j);
    numerator = (numerator * (-xJ)) % ed25519SubgroupOrder;
    final diff = (xI - xJ) % ed25519SubgroupOrder;
    denominator = (denominator * diff) % ed25519SubgroupOrder;
  }
  final inv = denominator.modInverse(ed25519SubgroupOrder);
  return (numerator * inv) % ed25519SubgroupOrder;
}

/// Reconstructs f(0) from share scalars at [indices].
BigInt lagrangeReconstructAtZero(List<int> indices, List<BigInt> shareScalars) {
  if (indices.length != shareScalars.length) {
    throw ArgumentError('indices and shareScalars length mismatch');
  }
  var secret = BigInt.zero;
  for (var i = 0; i < indices.length; i++) {
    final lambda = lagrangeCoefficientAtZero(indices[i], indices);
    secret = (secret + shareScalars[i] * lambda) % ed25519SubgroupOrder;
  }
  return secret;
}

/// Evaluates polynomial [coefficients] at participant [index] (Horner form).
BigInt evaluatePolynomialAtIndex(List<BigInt> coefficients, int index) {
  final x = participantIndexAsScalar(index);
  var result = BigInt.zero;
  for (var k = coefficients.length - 1; k >= 0; k--) {
    result = (result * x + coefficients[k]) % ed25519SubgroupOrder;
  }
  return result;
}
