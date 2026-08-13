/// [MlDsaShare] wire codec (v2, kind `0x09`).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/threshold_params.dart';
import '../../serialization/binary_codec.dart';
import '../../serialization/pqth_format.dart';
import '../../serialization/pqth_header.dart';
import '../../serialization/pqth_kind.dart';
import 'ml_dsa_share.dart';

@internal
abstract final class MlDsaShareCodec {
  static Uint8List encode(MlDsaShare share) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.mlDsaShare,
      scheme: share.params.scheme,
    );
    final participantBytes = Uint8List.fromList(share.participantId.codeUnits);
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(share.ceremonyId)
      ..writeBytes(share.params.toBytes())
      ..writeBytes(PqBytes.lengthPrefixed([participantBytes]))
      ..writeUint16Be(share.index)
      ..writeBytes(PqBytes.lengthPrefixed([share.ceremonySeedBytes()]));
    return writer.toBytes();
  }

  static MlDsaShare decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.mlDsaShare) {
      throw SerializationError('Expected MlDsaShare kind 0x09');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('MlDsaShare scheme mismatch');
    }
    final participantId = String.fromCharCodes(_readLp(reader));
    final index = reader.readUint16Be();
    final seed = _readLp(reader);
    reader.expectEnd();
    if (seed.length != 32) {
      throw SerializationError('MlDsaShare ceremony seed must be 32 bytes');
    }
    return MlDsaShare.simulate(
      params: params,
      ceremonyId: ceremonyId,
      participantId: participantId,
      index: index,
      ceremonySeed: seed,
    );
  }

  static Uint8List _readLp(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}
