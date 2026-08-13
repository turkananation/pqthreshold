/// Supported threshold scheme identifiers (v1).
library;

import '../errors/threshold_exception.dart';

/// Identifies the cryptographic scheme for a threshold instance.
///
/// Wire ordinals: `doc/PARAMS.md` §2.
enum SchemeId {
  /// FROST (Ed25519) + Feldman VSS + Gennaro DKG (`doc/FROST_PROFILE.md`).
  frostEd25519V1,
}

/// Hard limit on participants for [SchemeId.frostEd25519V1].
const int frostEd25519V1MaxParticipants = 255;

/// Extension methods for [SchemeId] wire encoding.
extension SchemeIdWire on SchemeId {
  /// Big-endian uint16 ordinal on the wire.
  int get wireOrdinal => switch (this) {
        SchemeId.frostEd25519V1 => 0x0001,
      };

  /// Documented maximum `n` for this scheme.
  int get maxParticipants => switch (this) {
        SchemeId.frostEd25519V1 => frostEd25519V1MaxParticipants,
      };
}

/// Parses a wire ordinal into [SchemeId].
SchemeId schemeIdFromWireOrdinal(int ordinal) {
  return switch (ordinal) {
    0x0001 => SchemeId.frostEd25519V1,
    _ => throw SerializationError('Unknown scheme ordinal: $ordinal'),
  };
}
