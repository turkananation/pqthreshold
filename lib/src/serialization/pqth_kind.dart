/// PQTH object kind bytes (`doc/SERIALIZATION.md` §3.2).
library;

import '../errors/threshold_exception.dart';

/// Durable object and message kind identifiers.
enum PqthObjectKind {
  /// [ThresholdParams] (`0x01`).
  thresholdParams(0x01),

  /// Share (`0x02`) — Phase 2.
  share(0x02),

  /// PublicKey (`0x03`) — Phase 3+.
  publicKey(0x03),

  /// PartialSignature (`0x04`) — Phase 4.
  partialSignature(0x04),

  /// Transcript (`0x05`) — Phase 3.
  transcript(0x05),

  /// ContinuityProof (`0x06`) — Phase 5.
  continuityProof(0x06);

  const PqthObjectKind(this.wireValue);

  /// Single-byte kind on the wire.
  final int wireValue;

  /// Parses a kind byte.
  static PqthObjectKind fromWire(int value) {
    for (final kind in PqthObjectKind.values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    if (value >= 0x10 && value <= 0x1F) {
      throw SerializationError(
        'Protocol message kind 0x${value.toRadixString(16)} is not a durable object',
      );
    }
    throw SerializationError('Unknown PQTH object kind: 0x${value.toRadixString(16)}');
  }
}
