/// DKG protocol message wire format (`doc/PROTOCOL_MESSAGES.md` §2–3).
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

/// Protocol message kind bytes for DKG (`doc/PROTOCOL_MESSAGES.md` §3.2).
abstract final class DkgWireKind {
  static const int round1 = 0x10;
  static const int round2 = 0x11;
  static const int complaint = 0x12;
  static const int response = 0x13;
  static const int finalize = 0x14;
}

/// Protocol message sub-kind bytes for DKG.
abstract final class DkgWireSubKind {
  static const int round1 = 0x01;
  static const int round2 = 0x02;
  static const int complaint = 0x03;
  static const int response = 0x04;
  static const int finalize = 0x05;
}

/// Typed wrapper for a canonical DKG protocol envelope.
final class DkgMessage {
  DkgMessage._({
    required this.kind,
    required this.subKind,
    required this.scheme,
    required this.ceremonyId,
    required this.senderIndex,
    required this.payload,
    required this.wireBytes,
  });

  /// Message kind byte (`0x10`..`0x14`).
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

  /// Full canonical wire bytes (used for transcript hashing).
  final Uint8List wireBytes;

  /// Recipient index for Round2 packages; null for broadcast messages.
  int? get recipientIndex {
    if (subKind != DkgWireSubKind.round2) return null;
    if (payload.length < 2) return null;
    return payload.buffer.asByteData(payload.offsetInBytes).getUint16(0, Endian.big);
  }

  /// Parses [bytes] into a [DkgMessage].
  factory DkgMessage.fromBytes(Uint8List bytes) {
    if (bytes.length < pqthHeaderLength + 1 + 16 + 2 + 4) {
      throw SerializationError('DKG message too short');
    }
    for (var i = 0; i < pqthMagicBytes.length; i++) {
      if (bytes[i] != pqthMagicBytes[i]) {
        throw SerializationError('Invalid PQTH magic in DKG message');
      }
    }
    final version = bytes[4];
    if (version != pqthFormatVersion) {
      throw SerializationError('Unsupported DKG message version: $version');
    }
    final kind = bytes[5];
    final schemeOrdinal =
        bytes.buffer.asByteData(bytes.offsetInBytes).getUint16(6, Endian.big);
    final scheme = schemeIdFromWireOrdinal(schemeOrdinal);
    final subKind = bytes[8];
    final ceremonyId = Uint8List.sublistView(bytes, 9, 25);
    final senderIndex =
        bytes.buffer.asByteData(bytes.offsetInBytes).getUint16(25, Endian.big);
    final payloadLength =
        bytes.buffer.asByteData(bytes.offsetInBytes).getUint32(27, Endian.big);
    final payloadStart = 31;
    if (bytes.length != payloadStart + payloadLength) {
      throw SerializationError('DKG message length mismatch');
    }
    final payload = Uint8List.sublistView(bytes, payloadStart, bytes.length);
    return DkgMessage._(
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
      throw WrongCeremony('DKG message ceremonyId mismatch');
    }
    if (scheme != params.scheme) {
      throw WrongCeremony('DKG message scheme mismatch');
    }
    if (senderIndex < 1 || senderIndex > params.n) {
      throw SerializationError('DKG senderIndex $senderIndex out of range');
    }
  }

  /// Encodes a Round1 package.
  @internal
  static DkgMessage round1({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required List<Uint8List> commitments,
  }) {
    _assertIndex(senderIndex, params.n);
    if (commitments.length != params.t) {
      throw InvalidParams('Round1 requires ${params.t} commitments');
    }
    final payload = BytesBuilder(copy: false)
      ..addByte(commitments.length)
      ..add(PqBytes.concat(commitments));
    return _encode(
      kind: DkgWireKind.round1,
      subKind: DkgWireSubKind.round1,
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      payload: payload.toBytes(),
    );
  }

  /// Encodes a Round2 package to [recipientIndex].
  @internal
  static DkgMessage round2({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required int recipientIndex,
    required Uint8List shareScalarLe,
  }) {
    _assertIndex(senderIndex, params.n);
    _assertIndex(recipientIndex, params.n);
    if (shareScalarLe.length != 32) {
      throw InvalidParams('Share scalar must be 32 bytes');
    }
    final writer = BinaryWriter()
      ..writeUint16Be(recipientIndex)
      ..writeBytes(shareScalarLe);
    return _encode(
      kind: DkgWireKind.round2,
      subKind: DkgWireSubKind.round2,
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      payload: writer.toBytes(),
    );
  }

  /// Parses Round1 commitments from [payload].
  static List<Uint8List> parseRound1Payload(Uint8List payload, int expectedT) {
    if (payload.isEmpty) {
      throw SerializationError('Empty Round1 payload');
    }
    final count = payload[0];
    if (count != expectedT) {
      throw SerializationError('Round1 coeffCount $count != expected $expectedT');
    }
    final expectedLen = 1 + count * 32;
    if (payload.length != expectedLen) {
      throw SerializationError('Invalid Round1 payload length');
    }
    return [
      for (var i = 0; i < count; i++)
        Uint8List.sublistView(payload, 1 + i * 32, 1 + (i + 1) * 32),
    ];
  }

  /// Parses Round2 share scalar from [payload] for [expectedRecipient].
  static Uint8List parseRound2Payload(Uint8List payload, int expectedRecipient) {
    if (payload.length != 34) {
      throw SerializationError('Round2 payload must be 34 bytes');
    }
    final recipient =
        payload.buffer.asByteData(payload.offsetInBytes).getUint16(0, Endian.big);
    if (recipient != expectedRecipient) {
      throw SerializationError('Round2 recipientIndex mismatch');
    }
    return Uint8List.sublistView(payload, 2, 34);
  }

  static DkgMessage _encode({
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
    return DkgMessage._(
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
}
