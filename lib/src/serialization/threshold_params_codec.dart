/// [ThresholdParams] wire codec (`doc/SERIALIZATION.md` §4.1).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import '../params/threshold_params.dart';
import 'binary_codec.dart';
import 'pqth_format.dart';
import 'pqth_header.dart';
import 'pqth_kind.dart';

/// Encodes and decodes [ThresholdParams] canonical bytes.
@internal
abstract final class ThresholdParamsCodec {
  /// Serializes [params] to canonical PQTH bytes.
  static Uint8List encode(ThresholdParams params) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.thresholdParams,
      scheme: params.scheme,
    );
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeUint16Be(params.t)
      ..writeUint16Be(params.n)
      ..writeUint32Be(params.scheme.maxParticipants);
    return writer.toBytes();
  }

  /// Deserializes [bytes] into validated [ThresholdParams].
  static ThresholdParams decode(Uint8List bytes) {
    if (bytes.length != thresholdParamsEncodedLength) {
      throw SerializationError(
        'Invalid ThresholdParams length: expected $thresholdParamsEncodedLength, got ${bytes.length}',
      );
    }
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.thresholdParams) {
      throw SerializationError(
        'Expected ThresholdParams kind 0x01, got 0x${header.kind.wireValue.toRadixString(16)}',
      );
    }
    final reader = BinaryReader(payload);
    final t = reader.readUint16Be();
    final n = reader.readUint16Be();
    final maxParticipants = reader.readUint32Be();
    reader.expectEnd();

    if (maxParticipants != header.scheme.maxParticipants) {
      throw SerializationError(
        'maxParticipants mismatch: wire=$maxParticipants expected=${header.scheme.maxParticipants}',
      );
    }

    return ThresholdParams.fromValidated(t: t, n: n, scheme: header.scheme);
  }
}
