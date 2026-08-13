/// Sealed error hierarchy for [pqthreshold](https://pub.dev/packages/pqthreshold).
///
/// Public APIs throw these types; internal code uses [Result] and maps at the
/// barrel. See `doc/API.md` §5.
library;

/// Base type for all recoverable threshold operation failures.
sealed class ThresholdException implements Exception {
  /// Creates an exception with a human-readable [message].
  const ThresholdException(this.message);

  /// Describes the failure; safe to log (must not contain secret material).
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// [ThresholdParams] or participant identity failed validation.
final class InvalidParams extends ThresholdException {
  /// Creates an invalid-parameters error.
  const InvalidParams(super.message);
}

/// Fewer than [ThresholdParams.t] shares were supplied.
final class InsufficientShares extends ThresholdException {
  /// Creates an insufficient-shares error.
  const InsufficientShares(super.message);
}

/// Shares or verification data are mutually inconsistent.
final class InconsistentShares extends ThresholdException {
  /// Creates an inconsistent-shares error.
  const InconsistentShares(super.message);
}

/// A partial signature failed validation or combination.
final class InvalidPartialSignature extends ThresholdException {
  /// Creates an invalid-partial-signature error.
  const InvalidPartialSignature(super.message);
}

/// Transcript hash chain or contents are invalid.
final class TranscriptMismatch extends ThresholdException {
  /// Creates a transcript mismatch error.
  const TranscriptMismatch(super.message);
}

/// A multi-party ceremony aborted (missing participants, complaints, etc.).
final class CeremonyAborted extends ThresholdException {
  /// Creates a ceremony-aborted error.
  const CeremonyAborted(super.message);
}

/// Object belongs to a different ceremony or parameter set.
final class WrongCeremony extends ThresholdException {
  /// Creates a wrong-ceremony error.
  const WrongCeremony(super.message);
}

/// Binary parse failure or unknown format version/kind/scheme.
final class SerializationError extends ThresholdException {
  /// Creates a serialization error.
  const SerializationError(super.message);
}

/// [SchemeId] is registered but ceremony/signing is not implemented yet (v2 M1+).
final class SchemeNotImplemented extends ThresholdException {
  /// Creates a not-implemented error for [scheme].
  const SchemeNotImplemented(super.message);
}
