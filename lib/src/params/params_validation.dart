/// Public validators for share-scoped parameters.
///
/// These checks previously lived only inside `@internal Share.create`, so a
/// third-party custodian could not validate a participant index or a participant
/// label without constructing a `Share` — which requires the secret scalar.
/// They are public here so a caller can check metadata it read from storage
/// before deciding whether to unwrap.
library;

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';

/// Maximum accepted length of a participant label, in UTF-16 code units.
///
/// Matches the check performed on construction. Note the historical wording of
/// the error message says "UTF-8 bytes" while the check counts UTF-16 code
/// units; the check is what is authoritative.
const int maxParticipantIdCodeUnits = 256;

/// Validates that [index] is a legal 1-based Shamir evaluation index for
/// [params], i.e. in `1..n`.
///
/// Throws [InvalidParams] otherwise.
void validateShareIndex(int index, ThresholdParams params) {
  if (index < 1 || index > params.n) {
    throw InvalidParams('Share index $index out of range 1..${params.n}');
  }
}

/// Validates a participant label.
///
/// A label must be non-empty and at most [maxParticipantIdCodeUnits] UTF-16
/// code units. Throws [InvalidParams] otherwise.
void validateParticipantId(String participantId) {
  if (participantId.isEmpty ||
      participantId.codeUnits.length > maxParticipantIdCodeUnits) {
    throw InvalidParams(
      'participantId must be 1..$maxParticipantIdCodeUnits UTF-8 bytes',
    );
  }
}