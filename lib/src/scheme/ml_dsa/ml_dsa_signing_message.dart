/// ML-DSA threshold signing wire messages (`doc/PROTOCOL_MESSAGES.md` §6).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/scheme_id.dart';
import '../../params/threshold_params.dart';
import '../../serialization/binary_codec.dart';
import '../../serialization/pqth_format.dart';
import '../../util/ceremony_id.dart';

/// Protocol message kind bytes for ML-DSA threshold signing.
abstract final class MlDsaWireKind {
  static const int round1 = 0x20;
  static const int round2 = 0x21;
  static const int round3 = 0x22;
}

/// Protocol message sub-kind bytes for ML-DSA threshold signing.
abstract final class MlDsaWireSubKind {
  static const int round1Commit = 0x01;
  static const int round2Reveal = 0x02;
  static const int round3Response = 0x03;
}

/// Typed wrapper for ML-DSA threshold signing protocol envelopes.
final class MlDsaSigningMessage {
  MlDsaSigningMessage._({
    required this.kind,
    required this.subKind,
    required this.scheme,
    required this.ceremonyId,
    required this.senderIndex,
    required this.sessionId,
    required this.payload,
    required this.wireBytes,
  });

  final int kind;
  final int subKind;
  final SchemeId scheme;
  final Uint8List ceremonyId;
  final int senderIndex;
  final Uint8List sessionId;
  final Uint8List payload;
  final Uint8List wireBytes;

  factory MlDsaSigningMessage.fromBytes(Uint8List bytes) {
    if (bytes.length < pqthHeaderLength + 1 + 16 + 2 + 32 + 4) {
      throw SerializationError('ML-DSA signing message too short');
    }
    for (var i = 0; i < pqthMagicBytes.length; i++) {
      if (bytes[i] != pqthMagicBytes[i]) {
        throw SerializationError('Invalid PQTH magic in ML-DSA message');
      }
    }
    final version = bytes[4];
    if (version != pqthFormatVersion) {
      throw SerializationError('Unsupported ML-DSA message version: $version');
    }
    final kind = bytes[5];
    if (kind != MlDsaWireKind.round1 &&
        kind != MlDsaWireKind.round2 &&
        kind != MlDsaWireKind.round3) {
      throw SerializationError(
        'Invalid ML-DSA wire kind: 0x${kind.toRadixString(16)}',
      );
    }
    final schemeOrdinal = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint16(6, Endian.big);
    final scheme = schemeIdFromWireOrdinal(schemeOrdinal);
    final subKind = bytes[8];
    final ceremonyId = Uint8List.sublistView(bytes, 9, 25);
    final senderIndex = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint16(25, Endian.big);
    final sessionId = Uint8List.sublistView(bytes, 27, 59);
    final payloadLen = bytes.buffer
        .asByteData(bytes.offsetInBytes)
        .getUint32(59, Endian.big);
    const payloadStart = 63;
    if (bytes.length < payloadStart + payloadLen) {
      throw SerializationError('Truncated ML-DSA message payload');
    }
    final payload = Uint8List.sublistView(
      bytes,
      payloadStart,
      payloadStart + payloadLen,
    );
    return MlDsaSigningMessage._(
      kind: kind,
      subKind: subKind,
      scheme: scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      sessionId: sessionId,
      payload: payload,
      wireBytes: bytes,
    );
  }

  factory MlDsaSigningMessage.round1({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List sessionId,
    required Uint8List commitmentHash,
  }) {
    _validateEnvelope(params, ceremonyId, senderIndex, sessionId);
    if (commitmentHash.length != 32) {
      throw InvalidParams('Round1 commitment hash must be 32 bytes');
    }
    return _encode(
      kind: MlDsaWireKind.round1,
      subKind: MlDsaWireSubKind.round1Commit,
      scheme: params.scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      sessionId: sessionId,
      payload: commitmentHash,
    );
  }

  factory MlDsaSigningMessage.round2({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List sessionId,
    required Uint8List revealBytes,
  }) {
    _validateEnvelope(params, ceremonyId, senderIndex, sessionId);
    return _encode(
      kind: MlDsaWireKind.round2,
      subKind: MlDsaWireSubKind.round2Reveal,
      scheme: params.scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      sessionId: sessionId,
      payload: revealBytes,
    );
  }

  factory MlDsaSigningMessage.round3({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List sessionId,
    required Uint8List responseBytes,
  }) {
    _validateEnvelope(params, ceremonyId, senderIndex, sessionId);
    return _encode(
      kind: MlDsaWireKind.round3,
      subKind: MlDsaWireSubKind.round3Response,
      scheme: params.scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      sessionId: sessionId,
      payload: responseBytes,
    );
  }

  static void _validateEnvelope(
    ThresholdParams params,
    Uint8List ceremonyId,
    int senderIndex,
    Uint8List sessionId,
  ) {
    validateCeremonyId(ceremonyId);
    if (sessionId.length != 32) {
      throw InvalidParams('sessionId must be 32 bytes');
    }
    if (senderIndex < 1 || senderIndex > params.n) {
      throw InvalidParams('senderIndex $senderIndex out of range');
    }
  }

  static MlDsaSigningMessage _encode({
    required int kind,
    required int subKind,
    required SchemeId scheme,
    required Uint8List ceremonyId,
    required int senderIndex,
    required Uint8List sessionId,
    required Uint8List payload,
  }) {
    final writer = BinaryWriter()
      ..writeBytes(Uint8List.fromList(pqthMagicBytes))
      ..writeUint8(pqthFormatVersion)
      ..writeUint8(kind)
      ..writeUint16Be(scheme.wireOrdinal)
      ..writeUint8(subKind)
      ..writeBytes(ceremonyId)
      ..writeUint16Be(senderIndex)
      ..writeBytes(sessionId)
      ..writeUint32Be(payload.length)
      ..writeBytes(payload);
    final wireBytes = writer.toBytes();
    return MlDsaSigningMessage._(
      kind: kind,
      subKind: subKind,
      scheme: scheme,
      ceremonyId: ceremonyId,
      senderIndex: senderIndex,
      sessionId: sessionId,
      payload: payload,
      wireBytes: wireBytes,
    );
  }

  Uint8List transcriptHash() => PqBytes.sha256(wireBytes);
}

/// Builds wire messages from Mithril bridge `wire_sign` JSON output.
@internal
List<MlDsaSigningMessage> mlDsaMessagesFromWireSignJson({
  required ThresholdParams params,
  required Uint8List ceremonyId,
  required Uint8List sessionId,
  required Map<String, dynamic> wireJson,
}) {
  final messages = <MlDsaSigningMessage>[];
  for (final entry in wireJson['round1'] as List<dynamic>) {
    final map = entry as Map<String, dynamic>;
    messages.add(
      MlDsaSigningMessage.round1(
        params: params,
        ceremonyId: ceremonyId,
        senderIndex: (map['sender_index'] as int) + 1,
        sessionId: sessionId,
        commitmentHash: base64Decode(map['hash_b64'] as String),
      ),
    );
  }
  for (final entry in wireJson['round2'] as List<dynamic>) {
    final map = entry as Map<String, dynamic>;
    messages.add(
      MlDsaSigningMessage.round2(
        params: params,
        ceremonyId: ceremonyId,
        senderIndex: (map['sender_index'] as int) + 1,
        sessionId: sessionId,
        revealBytes: base64Decode(map['reveal_b64'] as String),
      ),
    );
  }
  for (final entry in wireJson['round3'] as List<dynamic>) {
    final map = entry as Map<String, dynamic>;
    messages.add(
      MlDsaSigningMessage.round3(
        params: params,
        ceremonyId: ceremonyId,
        senderIndex: (map['sender_index'] as int) + 1,
        sessionId: sessionId,
        responseBytes: base64Decode(map['response_b64'] as String),
      ),
    );
  }
  return messages;
}

/// Writes [messages] into round-specific subdirs under [baseDir].
Future<void> writeMlDsaWireMessages({
  required Directory baseDir,
  required List<MlDsaSigningMessage> messages,
}) async {
  for (final message in messages) {
    final sub = switch (message.kind) {
      MlDsaWireKind.round1 => 'round1',
      MlDsaWireKind.round2 => 'round2',
      MlDsaWireKind.round3 => 'round3',
      _ => throw ArgumentError('invalid kind'),
    };
    final dir = Directory('${baseDir.path}/$sub');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/from-${message.senderIndex}.wire',
    ).writeAsBytes(message.wireBytes, flush: true);
  }
}

/// Loads all ML-DSA wire messages under [dir] (recursive round subdirs).
List<MlDsaSigningMessage> loadMlDsaWireMessages(Directory dir) {
  if (!dir.existsSync()) return const [];
  final messages = <MlDsaSigningMessage>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.wire')) continue;
    final bytes = entity.readAsBytesSync();
    if (bytes.isEmpty) continue;
    messages.add(MlDsaSigningMessage.fromBytes(bytes));
  }
  return messages;
}
