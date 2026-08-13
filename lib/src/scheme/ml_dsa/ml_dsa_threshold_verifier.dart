/// ML-DSA threshold signature verification via pqforge (`doc/ML_DSA_THRESHOLD_PROFILE.md` §1).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../../params/scheme_id.dart';
import 'ml_dsa_profile.dart';

/// Verifies threshold-produced ML-DSA signatures (FIPS 204 output shape).
abstract final class MlDsaThresholdVerifier {
  /// Verifies [signature] under [publicKey] using pqforge.
  ///
  /// Use after threshold combine once M2 signing is implemented; also used
  /// in tests and migration paths that hold a full ML-DSA key.
  static bool verify({
    required SchemeId scheme,
    required Uint8List publicKey,
    required Uint8List message,
    required Uint8List signature,
    Uint8List? context,
    bool preHash = false,
  }) {
    final profile = MlDsaThresholdProfile.fromScheme(scheme);
    if (publicKey.length != profile.publicKeyLength) {
      return false;
    }
    if (signature.length != profile.signatureLength) {
      return false;
    }
    return PqSignaturePrimitives.verify(
      profile.pqforgeAlgorithm,
      publicKey,
      message,
      signature,
      context: context,
      preHash: preHash,
    );
  }
}
