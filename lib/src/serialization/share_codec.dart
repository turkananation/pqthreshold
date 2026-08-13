/// [Share] wire codec (`doc/SERIALIZATION.md` §4.2).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../sharing/share.dart';
import 'binary_codec.dart';
import 'pqth_format.dart';
import 'pqth_header.dart';
import 'pqth_kind.dart';

/// Encodes and decodes [Share] objects.
@internal
abstract final class ShareCodec {
  /// Serializes [share] to canonical PQTH bytes.
  static Uint8List encode(Share share) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.share,
      scheme: share.params.scheme,
    );
    final participantBytes = Uint8List.fromList(share.participantId.codeUnits);
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(share.ceremonyId)
      ..writeBytes(share.params.toBytes())
      ..writeBytes(PqBytes.lengthPrefixed([participantBytes]))
      ..writeUint16Be(share.index)
      ..writeBytes(PqBytes.lengthPrefixed([share.secretShareBytes()]))
      ..writeBytes(PqBytes.lengthPrefixed([share.verificationData]));
    return writer.toBytes();
  }

  /// Deserializes [bytes] into a [Share].
  static Share decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.share) {
      throw SerializationError('Expected Share kind 0x02');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('Share scheme mismatch with header');
    }
    final participantId = String.fromCharCodes(_readLengthPrefixed(reader));
    final index = reader.readUint16Be();
    final secretShare = _readLengthPrefixed(reader);
    final verificationData = _readLengthPrefixed(reader);
    reader.expectEnd();

    if (secretShare.length != 32) {
      throw SerializationError('Share scalar must be 32 bytes');
    }
    return Share.create(
      params: params,
      ceremonyId: ceremonyId,
      participantId: participantId,
      index: index,
      secretShare: secretShare,
      verificationData: verificationData,
    );
  }

  static Uint8List _readLengthPrefixed(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}
