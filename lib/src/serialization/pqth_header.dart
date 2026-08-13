/// PQTH fixed header encode/decode (`doc/SERIALIZATION.md` §3.1).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import 'pqth_format.dart';
import 'pqth_kind.dart';

/// Parsed 8-byte PQTH object header.
final class PqthHeader {
  /// Creates a header.
  const PqthHeader({
    required this.version,
    required this.kind,
    required this.scheme,
  });

  /// Format version byte.
  final int version;

  /// Object kind.
  final PqthObjectKind kind;

  /// Scheme identifier.
  final SchemeId scheme;

  /// Encodes the fixed header.
  Uint8List toBytes() {
    return PqBytes.concat([
      Uint8List.fromList(pqthMagicBytes),
      Uint8List.fromList([version]),
      Uint8List.fromList([kind.wireValue]),
      _encodeSchemeOrdinal(scheme.wireOrdinal),
    ]);
  }

  static Uint8List _encodeSchemeOrdinal(int ordinal) {
    final out = Uint8List(2);
    out.buffer.asByteData().setUint16(0, ordinal, Endian.big);
    return out;
  }

  /// Parses and validates a header from the start of [bytes].
  static PqthHeader decode(Uint8List bytes) {
    if (bytes.length < pqthHeaderLength) {
      throw SerializationError(
        'Buffer too short for PQTH header (need $pqthHeaderLength bytes)',
      );
    }
    for (var i = 0; i < pqthMagicBytes.length; i++) {
      if (bytes[i] != pqthMagicBytes[i]) {
        throw SerializationError('Invalid PQTH magic bytes');
      }
    }
    final version = bytes[4];
    if (version != pqthFormatVersion) {
      throw SerializationError('Unsupported PQTH format version: $version');
    }
    final kind = PqthObjectKind.fromWire(bytes[5]);
    final schemeOrdinal = bytes.buffer.asByteData(bytes.offsetInBytes).getUint16(
          6,
          Endian.big,
        );
    final scheme = schemeIdFromWireOrdinal(schemeOrdinal);
    return PqthHeader(version: version, kind: kind, scheme: scheme);
  }

  /// Parses header and returns header + payload slice.
  @internal
  static (PqthHeader header, Uint8List payload) split(Uint8List bytes) {
    final header = decode(bytes);
    if (bytes.length < pqthHeaderLength) {
      throw SerializationError('Truncated PQTH object');
    }
    final payload = Uint8List.sublistView(bytes, pqthHeaderLength);
    return (header, payload);
  }
}
