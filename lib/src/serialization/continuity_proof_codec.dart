/// [ContinuityProof] wire codec (`doc/SERIALIZATION.md` §4.6).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../ceremony/continuity_proof.dart';
import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import '../serialization/binary_codec.dart';
import '../serialization/pqth_format.dart';
import '../serialization/pqth_header.dart';
import '../serialization/pqth_kind.dart';

/// Encodes and decodes [ContinuityProof] objects.
@internal
abstract final class ContinuityProofCodec {
  /// Serializes [proof] to canonical PQTH bytes.
  static Uint8List encode(ContinuityProof proof) {
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.continuityProof,
      scheme: SchemeId.frostEd25519V1,
    );
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(proof.oldCeremonyId)
      ..writeBytes(proof.newCeremonyId)
      ..writeBytes(proof.oldPublicKeyBytes)
      ..writeBytes(proof.newPublicKeyBytes)
      ..writeUint64Be(proof.signedAtUnixSeconds)
      ..writeBytes(proof.thresholdSignature);
    return writer.toBytes();
  }

  /// Deserializes [bytes] into a [ContinuityProof].
  static ContinuityProof decode(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.continuityProof) {
      throw SerializationError('Expected ContinuityProof kind 0x06');
    }
    final reader = BinaryReader(payload);
    final oldCeremonyId = reader.readBytes(16);
    final newCeremonyId = reader.readBytes(16);
    final oldPublicKeyBytes = reader.readBytes(32);
    final newPublicKeyBytes = reader.readBytes(32);
    final signedAt = reader.readUint64Be();
    final signature = reader.readBytes(64);
    reader.expectEnd();
    return ContinuityProof.create(
      oldCeremonyId: oldCeremonyId,
      newCeremonyId: newCeremonyId,
      oldPublicKeyBytes: oldPublicKeyBytes,
      newPublicKeyBytes: newPublicKeyBytes,
      signedAtUnixSeconds: signedAt,
      thresholdSignature: signature,
    );
  }
}
