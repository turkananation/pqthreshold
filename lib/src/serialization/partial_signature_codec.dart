/// [PartialSignature] wire codec (`doc/SERIALIZATION.md` §4.4).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import '../serialization/binary_codec.dart';
import '../serialization/pqth_format.dart';
import '../serialization/pqth_header.dart';
import '../serialization/pqth_kind.dart';
import '../signing/partial_signature.dart';

/// Encodes and decodes [PartialSignature] objects.
@internal
abstract final class PartialSignatureCodec {
  /// Serializes [partial] — omits ephemeral nonces (public material only).
  static Uint8List encode(PartialSignature partial) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.partialSignature,
      scheme: SchemeId.frostEd25519V1,
    );
    final partialBytes = PqBytes.concat([
      partial.hidingCommitment,
      partial.bindingCommitment,
      partial.partialScalar,
    ]);
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(partial.ceremonyId)
      ..writeBytes(partial.publicKeyFingerprint)
      ..writeUint16Be(partial.signerIndex)
      ..writeBytes(partial.messageBinding)
      ..writeBytes(PqBytes.lengthPrefixed([partialBytes]));
    return writer.toBytes();
  }

  /// Deserializes [bytes] into a [PartialSignature].
  static PartialSignature decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.partialSignature) {
      throw SerializationError('Expected PartialSignature kind 0x04');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final fingerprint = reader.readBytes(32);
    final signerIndex = reader.readUint16Be();
    final messageBinding = reader.readBytes(32);
    final partialBytes = _readLengthPrefixed(reader);
    reader.expectEnd();
    if (partialBytes.length != 96) {
      throw SerializationError('PartialSignature payload must be 96 bytes');
    }
    return PartialSignature.createFromCodec(
      ceremonyId: ceremonyId,
      publicKeyFingerprint: fingerprint,
      signerIndex: signerIndex,
      messageBinding: messageBinding,
      hidingCommitment: Uint8List.sublistView(partialBytes, 0, 32),
      bindingCommitment: Uint8List.sublistView(partialBytes, 32, 64),
      partialScalar: Uint8List.sublistView(partialBytes, 64, 96),
    );
  }

  static Uint8List _readLengthPrefixed(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}
