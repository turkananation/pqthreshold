/// Immutable threshold parameters (`t`-of-`n` and scheme).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors/result_bridge.dart';
import '../errors/threshold_exception.dart';
import '../serialization/threshold_params_codec.dart';
import 'scheme_id.dart';
import 'threshold_params_validation.dart';

/// Describes a threshold instance: quorum size, participant count, and scheme.
///
/// Spec: `doc/PARAMS.md`, `doc/API.md` §3.1.
final class ThresholdParams {
  ThresholdParams._({
    required this.t,
    required this.n,
    required this.scheme,
  });

  /// Minimum honest participants required.
  final int t;

  /// Total participants / shares.
  final int n;

  /// Cryptographic scheme for this threshold instance.
  final SchemeId scheme;

  /// Creates validated parameters.
  ///
  /// Throws [InvalidParams] when [t] or [n] violate scheme limits.
  factory ThresholdParams.tOfN({
    required int t,
    required int n,
    SchemeId scheme = SchemeId.frostEd25519V1,
  }) {
    unwrapParamsValidation(supportedSchemeValidator().validate(scheme));
    return switch (scheme) {
      SchemeId.frostEd25519V1 => _fromValidated(
          unwrapParamsValidation(
            frostEd25519V1ParamsValidator().validate((t, n)),
          ),
          scheme,
        ),
    };
  }

  static ThresholdParams _fromValidated((int, int) pair, SchemeId scheme) {
    return ThresholdParams._(t: pair.$1, n: pair.$2, scheme: scheme);
  }

  /// Canonical serialized bytes (`doc/SERIALIZATION.md` §4.1).
  Uint8List toBytes() => ThresholdParamsCodec.encode(this);

  /// Parses canonical bytes.
  ///
  /// Throws [SerializationError] for malformed wire data.
  /// Throws [InvalidParams] when decoded values fail semantic validation.
  factory ThresholdParams.fromBytes(Uint8List bytes) {
    return ThresholdParamsCodec.decode(bytes);
  }

  /// Internal success path for deserialization after wire checks.
  @internal
  factory ThresholdParams.fromValidated({
    required int t,
    required int n,
    required SchemeId scheme,
  }) =>
      ThresholdParams.tOfN(t: t, n: n, scheme: scheme);

  @override
  bool operator ==(Object other) {
    return other is ThresholdParams &&
        other.t == t &&
        other.n == n &&
        other.scheme == scheme;
  }

  @override
  int get hashCode => Object.hash(t, n, scheme);

  @override
  String toString() => 'ThresholdParams($t-of-$n, $scheme)';
}
