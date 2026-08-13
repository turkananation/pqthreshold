/// [MlDsaPublicKey] wire codec (`doc/ML_DSA_THRESHOLD_PROFILE.md` §6).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../errors/threshold_exception.dart';
import '../../params/threshold_params.dart';
import '../../serialization/binary_codec.dart';
import '../../serialization/pqth_format.dart';
import '../../serialization/pqth_header.dart';
import '../../serialization/pqth_kind.dart';
import 'ml_dsa_profile.dart';
import 'ml_dsa_share.dart';

@internal
abstract final class MlDsaPublicKeyCodec {
  static Uint8List encode(MlDsaPublicKey publicKey) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.mlDsaPublicKey,
      scheme: publicKey.params.scheme,
    );
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(publicKey.ceremonyId)
      ..writeBytes(publicKey.params.toBytes())
      ..writeBytes(_lengthPrefixed(publicKey.bytes));
    return writer.toBytes();
  }

  static MlDsaPublicKey decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.mlDsaPublicKey) {
      throw SerializationError('Expected MlDsaPublicKey kind 0x07');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('MlDsaPublicKey scheme mismatch');
    }
    final pkBytes = _readLengthPrefixed(reader);
    reader.expectEnd();
    final profile = MlDsaThresholdProfile.fromScheme(params.scheme);
    if (pkBytes.length != profile.publicKeyLength) {
      throw SerializationError('Invalid ML-DSA public key length');
    }
    return MlDsaPublicKey.create(
      params: params,
      ceremonyId: ceremonyId,
      publicKeyBytes: pkBytes,
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
