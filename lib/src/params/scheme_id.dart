/// Supported threshold scheme identifiers (v1 + v2 registry).
library;

import '../errors/threshold_exception.dart';

/// Identifies the cryptographic scheme for a threshold instance.
///
/// Wire ordinals: `doc/PARAMS.md` §2, [ADR-004](doc/adr/004-pq-threshold-schemes.md).
enum SchemeId {
  /// FROST (Ed25519) + Feldman VSS + Gennaro DKG (`doc/FROST_PROFILE.md`).
  frostEd25519V1,

  /// Threshold ML-DSA-44 (FIPS 204) — M1 registry, M3 signing target.
  mlDsa44ThresholdV1,

  /// Threshold ML-DSA-65 (FIPS 204) — primary v2 PQ root (M2).
  mlDsa65ThresholdV1,

  /// Threshold ML-DSA-87 (FIPS 204) — M4 target.
  mlDsa87ThresholdV1,

  /// Threshold SLH-DSA-Shake-128f (FIPS 205) — M5+.
  slhDsa128fThresholdV1,

  /// Dual Ed25519 + ML-DSA-65 organizational root — M5+.
  hybridFrostMlDsa65V1,
}

/// Hard limit on participants for [SchemeId.frostEd25519V1].
const int frostEd25519V1MaxParticipants = 255;

/// Hard limit on participants for v2 PQ small-set schemes (ADR-004).
const int pqThresholdSmallSetMaxParticipants = 8;

/// Extension methods for [SchemeId] wire encoding.
extension SchemeIdWire on SchemeId {
  /// Big-endian uint16 ordinal on the wire.
  int get wireOrdinal => switch (this) {
        SchemeId.frostEd25519V1 => 0x0001,
        SchemeId.mlDsa44ThresholdV1 => 0x0002,
        SchemeId.mlDsa65ThresholdV1 => 0x0003,
        SchemeId.mlDsa87ThresholdV1 => 0x0004,
        SchemeId.slhDsa128fThresholdV1 => 0x0005,
        SchemeId.hybridFrostMlDsa65V1 => 0x0006,
      };

  /// Documented maximum `n` for this scheme.
  int get maxParticipants => switch (this) {
        SchemeId.frostEd25519V1 => frostEd25519V1MaxParticipants,
        SchemeId.mlDsa44ThresholdV1 ||
        SchemeId.mlDsa65ThresholdV1 ||
        SchemeId.mlDsa87ThresholdV1 ||
        SchemeId.slhDsa128fThresholdV1 ||
        SchemeId.hybridFrostMlDsa65V1 =>
          pqThresholdSmallSetMaxParticipants,
      };

  /// Whether this scheme uses post-quantum combined signatures (v2).
  bool get isPostQuantumThreshold => switch (this) {
        SchemeId.frostEd25519V1 => false,
        _ => true,
      };
}

/// Parses a wire ordinal into [SchemeId].
SchemeId schemeIdFromWireOrdinal(int ordinal) {
  return switch (ordinal) {
    0x0001 => SchemeId.frostEd25519V1,
    0x0002 => SchemeId.mlDsa44ThresholdV1,
    0x0003 => SchemeId.mlDsa65ThresholdV1,
    0x0004 => SchemeId.mlDsa87ThresholdV1,
    0x0005 => SchemeId.slhDsa128fThresholdV1,
    0x0006 => SchemeId.hybridFrostMlDsa65V1,
    _ => throw SerializationError('Unknown scheme ordinal: $ordinal'),
  };
}
