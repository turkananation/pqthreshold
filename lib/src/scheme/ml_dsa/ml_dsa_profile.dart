/// ML-DSA threshold profile helpers (`doc/ML_DSA_THRESHOLD_PROFILE.md`).
library;

import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/scheme_id.dart';

/// Maps pqthreshold ML-DSA [SchemeId] values to pqforge algorithms.
enum MlDsaThresholdProfile {
  /// ML-DSA-44 (NIST category 2).
  mlDsa44(SchemeId.mlDsa44ThresholdV1, PqSignatureAlgorithm.mlDsa44),

  /// ML-DSA-65 (NIST category 3) — primary v2 target.
  mlDsa65(SchemeId.mlDsa65ThresholdV1, PqSignatureAlgorithm.mlDsa65),

  /// ML-DSA-87 (NIST category 5).
  mlDsa87(SchemeId.mlDsa87ThresholdV1, PqSignatureAlgorithm.mlDsa87);

  const MlDsaThresholdProfile(this.schemeId, this.pqforgeAlgorithm);

  /// Corresponding [SchemeId].
  final SchemeId schemeId;

  /// pqforge verification algorithm.
  final PqSignatureAlgorithm pqforgeAlgorithm;

  /// Expected FIPS 204 public key length.
  int get publicKeyLength => pqforgeAlgorithm.publicKeyBytes;

  /// Expected FIPS 204 signature length.
  int get signatureLength => pqforgeAlgorithm.signatureBytes;

  /// Resolves [scheme] to a profile.
  static MlDsaThresholdProfile fromScheme(SchemeId scheme) {
    for (final profile in values) {
      if (profile.schemeId == scheme) return profile;
    }
    throw InvalidParams('Scheme $scheme is not an ML-DSA threshold profile');
  }

  /// Whether [scheme] is one of the ML-DSA threshold profiles (not hybrid).
  static bool matchesScheme(SchemeId scheme) {
    return switch (scheme) {
      SchemeId.mlDsa44ThresholdV1 ||
      SchemeId.mlDsa65ThresholdV1 ||
      SchemeId.mlDsa87ThresholdV1 =>
        true,
      _ => false,
    };
  }
}
