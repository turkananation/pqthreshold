/// FROST signing protocol wire messages (`doc/PROTOCOL_MESSAGES.md` §5).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/scheme_id.dart';
import '../params/threshold_params.dart';
import '../serialization/binary_codec.dart';
import '../serialization/pqth_format.dart';
import '../util/ceremony_id.dart';

/// Protocol message kind bytes for FROST signing.
abstract final class FrostWireKind {
  static const int round1 = 0x15;
  static const int round2 = 0x16;
}

/// Protocol message sub-kind bytes for FROST signing.
abstract final class FrostWireSubKind {
  static const int round1 = 0x01;
  static const int round2 = 0x02;
}

/// Typed wrapper for a canonical FROST signing protocol envelope.
final class FrostSigningMessage {
  FrostSigningMessage._({
    required this.kind,
    required this.subKind,
    required this.scheme,
    required this.ceremonyId,
    required this.senderIndex,
    required this.payload,
    required this.wireBytes,
  });

  /// Message kind byte (`0x15` or `0x16`).
  final int kind;

  /// Message sub-kind byte.
  final int subKind;

  /// Scheme identifier.
  final SchemeId scheme;

  /// Ceremony binding.
  final Uint8List ceremonyId;

  /// 1-based sender index.
  final int senderIndex;

  /// Message-specific payload (without envelope).
  final Uint8List payload;

  /// Full canonical wire bytes.
  final Uint8List wireBytes;

  /// Parses [bytes] into a [FrostSigningMessage].
  factory FrostSigningMessage.fromBytes(Uint8List bytes) {
    if (bytes.length < pqthHeaderLength + 1 + 16 + 2 + 4) {
      throw SerializationError('FROST message too short');
    }
    for (var i = 0; i < pqthMagicBytes.length; i++) {
      if (bytes[i] != pqthMagicBytes[i]) {
        throw SerializationError('Invalid PQTH magic in FROST message');
      }
    }
    final version = bytes[4];
    if (version != pqthFormatVersion) {
      throw SerializationError('Unsupported FROST message version: $version');
    }
    final kind = bytes[5];
    final schemeOrdinal = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint16(6, Endian.big);
    final scheme = schemeIdFromWireOrdinal(schemeOrdinal);
    final subKind = bytes[8];
    final ceremonyId = Uint8List.sublistView(bytes, 9, 25);
    final senderIndex = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint16(25, Endian.big);
    final payloadLength = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint32(27, Endian.big);
    const payloadStart = 31;
    if (bytes.length != payloadStart + payloadLength) {
      throw SerializationError('FROST message length mismatch');
    }
    final payload = Uint8List.sublistView(bytes, payloadStart, bytes.length);
    return FrostSigningMessage._(
      kind: kind,
      subKind: subKind,
      scheme: scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      payload: payload,
      wireBytes: bytes,
    );
  }

  /// Validates binding against expected ceremony and params.
  void assertBinding({
    required ThresholdParams params,
    required Uint8List ceremonyId,
  }) {
    if (!PqBytes.constantTimeEquals(this.ceremonyId, ceremonyId)) {
      throw WrongCeremony('FROST message ceremonyId mismatch');
    }
    if (scheme != params.scheme) {
      throw WrongCeremony('FROST message scheme mismatch');
    }
    if (senderIndex < 1 || senderIndex > params.n) {
      throw SerializationError('FROST senderIndex $senderIndex out of range');
    }
  }

  /// Round-one commitments broadcast.
  @internal
  static FrostSigningMessage round1({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List messageBinding,
    required Uint8List hidingCommitment,
    required Uint8List bindingCommitment,
  }) {
    _assertIndex(senderIndex, params.n);
    _assertLen32(messageBinding, 'messageBinding');
    _assertLen32(hidingCommitment, 'hidingCommitment');
    _assertLen32(bindingCommitment, 'bindingCommitment');
    final payload = PqBytes.concat([
      messageBinding,
      hidingCommitment,
      bindingCommitment,
    ]);
    return _encode(
      kind: FrostWireKind.round1,
      subKind: FrostWireSubKind.round1,
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      payload: payload,
    );
  }

  /// Round-two partial scalar.
  @internal
  static FrostSigningMessage round2({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List messageBinding,
    required Uint8List partialScalarLe,
  }) {
    _assertIndex(senderIndex, params.n);
    _assertLen32(messageBinding, 'messageBinding');
    _assertLen32(partialScalarLe, 'partialScalar');
    final payload = PqBytes.concat([messageBinding, partialScalarLe]);
    return _encode(
      kind: FrostWireKind.round2,
      subKind: FrostWireSubKind.round2,
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      payload: payload,
    );
  }

  /// Parses Round1 payload fields.
  static ({
    Uint8List messageBinding,
    Uint8List hidingCommitment,
    Uint8List bindingCommitment,
  })
  parseRound1Payload(Uint8List payload) {
    if (payload.length != 96) {
      throw SerializationError('FROST Round1 payload must be 96 bytes');
    }
    return (
      messageBinding: Uint8List.sublistView(payload, 0, 32),
      hidingCommitment: Uint8List.sublistView(payload, 32, 64),
      bindingCommitment: Uint8List.sublistView(payload, 64, 96),
    );
  }

  /// Parses Round2 payload fields.
  static ({Uint8List messageBinding, Uint8List partialScalarLe})
  parseRound2Payload(Uint8List payload) {
    if (payload.length != 64) {
      throw SerializationError('FROST Round2 payload must be 64 bytes');
    }
    return (
      messageBinding: Uint8List.sublistView(payload, 0, 32),
      partialScalarLe: Uint8List.sublistView(payload, 32, 64),
    );
  }

  static FrostSigningMessage _encode({
    required int kind,
    required int subKind,
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List payload,
  }) {
    validateCeremonyId(ceremonyId);
    final schemeBytes = Uint8List(2)
      ..buffer.asByteData().setUint16(0, params.scheme.wireOrdinal, Endian.big);
    final writer = BinaryWriter()
      ..writeBytes(Uint8List.fromList(pqthMagicBytes))
      ..writeUint8(pqthFormatVersion)
      ..writeUint8(kind)
      ..writeBytes(schemeBytes)
      ..writeUint8(subKind)
      ..writeBytes(ceremonyId)
      ..writeUint16Be(senderIndex)
      ..writeBytes(PqBytes.lengthPrefixed([payload]));
    final wire = writer.toBytes();
    return FrostSigningMessage._(
      kind: kind,
      subKind: subKind,
      scheme: params.scheme,
      ceremonyId: Uint8List.fromList(ceremonyId),
      senderIndex: senderIndex,
      payload: payload,
      wireBytes: wire,
    );
  }

  static void _assertIndex(int index, int n) {
    if (index < 1 || index > n) {
      throw InvalidParams('Participant index $index out of range 1..$n');
    }
  }

  static void _assertLen32(Uint8List bytes, String label) {
    if (bytes.length != 32) {
      throw InvalidParams('$label must be 32 bytes');
    }
  }
}
