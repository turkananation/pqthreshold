/// Post-quantum threshold scheme capabilities and pqforge mapping (v2).
library;

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';

/// Ceremony types for capability checks.
enum ThresholdCeremonyKind {
  /// C1 distributed key generation.
  rootDkg,

  /// C3 threshold signing.
  thresholdSign,

  /// C5 rotation with continuity proof.
  rotation,
}

/// Production and API readiness for a [SchemeId].
enum SchemeMilestone {
  /// Shipped in v1.
  production,

  /// Registry + verify path only (M1).
  alpha,

  /// DKG + sign in development (M2).
  beta,

  /// Not yet specified.
  planned,
}

/// Static metadata for each [SchemeId] (ADR-004).
abstract final class SchemeCapabilities {
  /// Current implementation milestone.
  static SchemeMilestone milestone(SchemeId scheme) => switch (scheme) {
    SchemeId.frostEd25519V1 => SchemeMilestone.production,
    SchemeId.mlDsa44ThresholdV1 ||
    SchemeId.mlDsa65ThresholdV1 ||
    SchemeId.mlDsa87ThresholdV1 => SchemeMilestone.beta,
    SchemeId.slhDsa128fThresholdV1 ||
    SchemeId.hybridFrostMlDsa65V1 => SchemeMilestone.planned,
  };

  /// Whether [ceremony] is implemented for [scheme].
  static bool supports(SchemeId scheme, ThresholdCeremonyKind ceremony) {
    if (milestone(scheme) == SchemeMilestone.production) {
      return switch (ceremony) {
        ThresholdCeremonyKind.rootDkg ||
        ThresholdCeremonyKind.thresholdSign ||
        ThresholdCeremonyKind.rotation => scheme == SchemeId.frostEd25519V1,
      };
    }
    // M2 beta: ML-DSA-44 in-process simulate (Tier 2) only.
    if (scheme == SchemeId.mlDsa44ThresholdV1 &&
        milestone(scheme) == SchemeMilestone.beta) {
      return ceremony == ThresholdCeremonyKind.thresholdSign ||
          ceremony == ThresholdCeremonyKind.rootDkg;
    }
    return false;
  }

  /// Throws [SchemeNotImplemented] if [scheme] is not production-ready for ceremonies.
  static void requireProductionCeremony(
    SchemeId scheme,
    ThresholdCeremonyKind ceremony,
  ) {
    if (!supports(scheme, ceremony)) {
      throw SchemeNotImplemented(
        'Ceremony $ceremony is not implemented for $scheme '
        '(milestone: ${milestone(scheme).name})',
      );
    }
  }

  /// Human-readable scheme label for logs and CLI.
  static String displayName(SchemeId scheme) => switch (scheme) {
    SchemeId.frostEd25519V1 => 'FROST Ed25519 v1',
    SchemeId.mlDsa44ThresholdV1 => 'Threshold ML-DSA-44 v1',
    SchemeId.mlDsa65ThresholdV1 => 'Threshold ML-DSA-65 v1',
    SchemeId.mlDsa87ThresholdV1 => 'Threshold ML-DSA-87 v1',
    SchemeId.slhDsa128fThresholdV1 => 'Threshold SLH-DSA-128f v1',
    SchemeId.hybridFrostMlDsa65V1 => 'Hybrid FROST + ML-DSA-65 v1',
  };

  /// Whether [scheme] uses ML-DSA verify via pqforge.
  static bool isMlDsaThreshold(SchemeId scheme) => switch (scheme) {
    SchemeId.mlDsa44ThresholdV1 ||
    SchemeId.mlDsa65ThresholdV1 ||
    SchemeId.mlDsa87ThresholdV1 ||
    SchemeId.hybridFrostMlDsa65V1 => true,
    _ => false,
  };
}
