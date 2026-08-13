/// Ceremony identifier validation (`doc/PARAMS.md` §5).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';

/// Required byte length for a ceremony identifier.
const int ceremonyIdLength = 16;

/// Validates [ceremonyId] for use in ceremonies and durable objects.
///
/// Throws [InvalidParams] when invalid.
void validateCeremonyId(Uint8List ceremonyId) {
  if (ceremonyId.length != ceremonyIdLength) {
    throw InvalidParams(
      'ceremonyId must be exactly $ceremonyIdLength bytes (got ${ceremonyId.length})',
    );
  }
  if (_isAllZero(ceremonyId)) {
    throw InvalidParams('ceremonyId must not be all zero');
  }
}

/// Generates a new random ceremony identifier.
Uint8List generateCeremonyId() {
  var id = PqBytes.randomBytes(ceremonyIdLength);
  // Negligible collision with rejection sampling; retry on all-zero.
  while (_isAllZero(id)) {
    id = PqBytes.randomBytes(ceremonyIdLength);
  }
  return id;
}

bool _isAllZero(Uint8List bytes) {
  for (final b in bytes) {
    if (b != 0) {
      return false;
    }
  }
  return true;
}
