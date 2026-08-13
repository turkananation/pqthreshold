/// [PublicKey] wire codec (`doc/SERIALIZATION.md` §4.3).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../sharing/share.dart';
import 'binary_codec.dart';
import 'pqth_format.dart';
import 'pqth_header.dart';
import 'pqth_kind.dart';

/// Encodes and decodes [PublicKey] objects.
@internal
abstract final class PublicKeyCodec {
  /// Serializes [publicKey] to canonical PQTH bytes.
  static Uint8List encode(PublicKey publicKey) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.publicKey,
      scheme: publicKey.params.scheme,
    );
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(publicKey.ceremonyId)
      ..writeBytes(publicKey.params.toBytes())
      ..writeBytes(_lengthPrefixed(publicKey.bytes));
    return writer.toBytes();
  }

  /// Deserializes [bytes] into a [PublicKey].
  static PublicKey decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.publicKey) {
      throw SerializationError('Expected PublicKey kind 0x03');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('PublicKey scheme mismatch with header');
    }
    final publicKeyBytes = _readLengthPrefixed(reader);
    reader.expectEnd();
    if (publicKeyBytes.length != 32) {
      throw SerializationError('Ed25519 public key must be 32 bytes');
    }
    return PublicKey.create(
      params: params,
      ceremonyId: ceremonyId,
      publicKeyBytes: publicKeyBytes,
    );
  }

  static Uint8List _lengthPrefixed(Uint8List payload) {
    final writer = BinaryWriter()
      ..writeUint32Be(payload.length)
      ..writeBytes(payload);
    return writer.toBytes();
  }

  static Uint8List _readLengthPrefixed(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}
