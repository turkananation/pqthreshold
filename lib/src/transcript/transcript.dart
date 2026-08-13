/// Append-only ceremony audit log (`doc/API.md` §3.5, `doc/SERIALIZATION.md` §4.5).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart' hide PublicKey;

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../serialization/binary_codec.dart';
import '../serialization/pqth_format.dart';
import '../serialization/pqth_header.dart';
import '../serialization/pqth_kind.dart';
import '../serialization/public_key_codec.dart';
import '../sharing/share.dart';
import '../util/ceremony_id.dart';

/// Hash-chain transcript of public ceremony data only.
final class Transcript {
  Transcript._({
    required this.ceremonyId,
    required this.params,
    required List<String> participantIds,
    required this._entries,
    required this._prevHash,
    required this._sealed,
    required this._outcome,
    required this._abortReason,
    this._finalPublicKey,
    this._rootHash,
  }) : _participantIds = List.unmodifiable(participantIds);

  /// Ceremony identifier.
  final Uint8List ceremonyId;

  /// Threshold parameters.
  final ThresholdParams params;

  final List<String> _participantIds;
  final List<_TranscriptEntry> _entries;
  Uint8List _prevHash;
  bool _sealed;
  int _outcome;
  String _abortReason;
  PublicKey? _finalPublicKey;
  Uint8List? _rootHash;

  /// Creates an empty transcript for a ceremony.
  factory Transcript.create({
    required Uint8List ceremonyId,
    required ThresholdParams params,
    required List<String> participantIds,
  }) {
    validateCeremonyId(ceremonyId);
    if (participantIds.length != params.n) {
      throw InvalidParams('participantIds length must equal n=${params.n}');
    }
    return Transcript._(
      ceremonyId: Uint8List.fromList(ceremonyId),
      params: params,
      participantIds: participantIds,
      entries: <_TranscriptEntry>[],
      prevHash: Uint8List(32),
      sealed: false,
      outcome: 0,
      abortReason: '',
    );
  }

  /// Records a public round message hash.
  void appendRound({
    required int round,
    required int senderIndex,
    required Uint8List messageBytes,
  }) {
    if (_sealed) {
      throw TranscriptMismatch('Transcript already sealed');
    }
    if (round < 0 || round > 255) {
      throw InvalidParams('Transcript round out of range');
    }
    if (senderIndex < 1 || senderIndex > params.n) {
      throw InvalidParams('Transcript senderIndex out of range');
    }
    final messageHash = PqBytes.sha256(messageBytes);
    final entryHash = _hashEntry(
      prevHash: _prevHash,
      round: round,
      senderIndex: senderIndex,
      messageHash: messageHash,
    );
    _entries.add(
      _TranscriptEntry(
        round: round,
        senderIndex: senderIndex,
        messageHash: messageHash,
        prevHash: Uint8List.fromList(_prevHash),
        entryHash: entryHash,
      ),
    );
    _prevHash = entryHash;
  }

  /// Seals the transcript with ceremony outcome.
  Uint8List seal({
    PublicKey? finalPublicKey,
    required bool success,
    String? abortReason,
  }) {
    if (_sealed) {
      throw TranscriptMismatch('Transcript already sealed');
    }
    _sealed = true;
    _outcome = success ? 0 : 1;
    _abortReason = success ? '' : (abortReason ?? 'ceremony aborted');
    _finalPublicKey = finalPublicKey;
    _rootHash = _computeRootHash();
    return Uint8List.fromList(_rootHash!);
  }

  /// Verifies hash chain integrity.
  bool verify() {
    if (!_sealed || _rootHash == null) {
      return false;
    }
    var prev = Uint8List(32);
    for (final entry in _entries) {
      if (!PqBytes.constantTimeEquals(entry.prevHash, prev)) {
        return false;
      }
      final expected = _hashEntry(
        prevHash: entry.prevHash,
        round: entry.round,
        senderIndex: entry.senderIndex,
        messageHash: entry.messageHash,
      );
      if (!PqBytes.constantTimeEquals(entry.entryHash, expected)) {
        return false;
      }
      prev = entry.entryHash;
    }
    return PqBytes.constantTimeEquals(_computeRootHash(), _rootHash!);
  }

  /// Canonical serialized bytes.
  Uint8List toBytes() {
    if (!_sealed || _rootHash == null) {
      throw TranscriptMismatch('Transcript must be sealed before encoding');
    }
    final header = PqthHeader(
      version: pqthFormatVersion,
      kind: PqthObjectKind.transcript,
      scheme: params.scheme,
    );
    final writer = BinaryWriter()
      ..writeBytes(header.toBytes())
      ..writeBytes(ceremonyId)
      ..writeBytes(params.toBytes());
    for (final id in _participantIds) {
      writer.writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(id.codeUnits)]),
      );
    }
    writer
      ..writeUint32Be(_entries.length)
      ..writeBytes(_encodeEntries())
      ..writeUint8(_outcome)
      ..writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(_abortReason.codeUnits)]),
      );
    if (_finalPublicKey != null) {
      writer.writeBytes(
        PqBytes.lengthPrefixed([PublicKeyCodec.encode(_finalPublicKey!)]),
      );
    } else {
      writer.writeBytes(PqBytes.lengthPrefixed([Uint8List(0)]));
    }
    writer.writeBytes(_rootHash!);
    return writer.toBytes();
  }

  /// Parses a sealed transcript.
  factory Transcript.fromBytes(Uint8List bytes) {
    final (header, payload) = PqthHeader.split(bytes);
    if (header.kind != PqthObjectKind.transcript) {
      throw SerializationError('Expected Transcript kind 0x05');
    }
    final reader = BinaryReader(payload);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    if (params.scheme != header.scheme) {
      throw SerializationError('Transcript scheme mismatch');
    }
    final participantIds = <String>[];
    for (var i = 0; i < params.n; i++) {
      participantIds.add(_readLengthPrefixedUtf8(reader));
    }
    final entryCount = reader.readUint32Be();
    final entries = <_TranscriptEntry>[];
    var prevHash = Uint8List(32);
    for (var i = 0; i < entryCount; i++) {
      final round = reader.readUint8();
      final senderIndex = reader.readUint16Be();
      final messageHash = reader.readBytes(32);
      final storedPrev = reader.readBytes(32);
      final entryHash = _hashEntry(
        prevHash: storedPrev,
        round: round,
        senderIndex: senderIndex,
        messageHash: messageHash,
      );
      entries.add(
        _TranscriptEntry(
          round: round,
          senderIndex: senderIndex,
          messageHash: messageHash,
          prevHash: storedPrev,
          entryHash: entryHash,
        ),
      );
      prevHash = entryHash;
    }
    final outcome = reader.readUint8();
    final abortReason = _readLengthPrefixedUtf8(reader);
    final pkBytes = _readLengthPrefixedBytes(reader);
    PublicKey? finalPublicKey;
    if (pkBytes.isNotEmpty) {
      finalPublicKey = PublicKey.fromBytes(pkBytes);
    }
    final rootHash = reader.readBytes(32);
    reader.expectEnd();
    final transcript = Transcript._(
      ceremonyId: ceremonyId,
      params: params,
      participantIds: participantIds,
      entries: entries,
      prevHash: prevHash,
      sealed: true,
      outcome: outcome,
      abortReason: abortReason,
      finalPublicKey: finalPublicKey,
      rootHash: rootHash,
    );
    if (!transcript.verify()) {
      throw TranscriptMismatch('Transcript hash chain invalid');
    }
    return transcript;
  }

  /// In-progress checkpoint for DKG dir transport (v2).
  @internal
  Uint8List exportWorkingCheckpoint() {
    final writer = BinaryWriter()
      ..writeBytes(ceremonyId)
      ..writeBytes(params.toBytes());
    for (final id in _participantIds) {
      writer.writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(id.codeUnits)]),
      );
    }
    writer
      ..writeUint32Be(_entries.length)
      ..writeBytes(_encodeEntries())
      ..writeBytes(_prevHash)
      ..writeUint8(_sealed ? 1 : 0)
      ..writeUint8(_outcome)
      ..writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(_abortReason.codeUnits)]),
      );
    return writer.toBytes();
  }

  /// Restores [exportWorkingCheckpoint] bytes.
  @internal
  factory Transcript.fromWorkingCheckpoint(Uint8List bytes) {
    final reader = BinaryReader(bytes);
    final ceremonyId = reader.readBytes(16);
    final params = ThresholdParams.fromBytes(
      reader.readBytes(thresholdParamsEncodedLength),
    );
    final participantIds = <String>[];
    for (var i = 0; i < params.n; i++) {
      participantIds.add(_readLengthPrefixedUtf8(reader));
    }
    final entryCount = reader.readUint32Be();
    final entries = <_TranscriptEntry>[];
    for (var i = 0; i < entryCount; i++) {
      final round = reader.readUint8();
      final senderIndex = reader.readUint16Be();
      final messageHash = reader.readBytes(32);
      final storedPrev = reader.readBytes(32);
      final entryHash = _hashEntry(
        prevHash: storedPrev,
        round: round,
        senderIndex: senderIndex,
        messageHash: messageHash,
      );
      entries.add(
        _TranscriptEntry(
          round: round,
          senderIndex: senderIndex,
          messageHash: messageHash,
          prevHash: storedPrev,
          entryHash: entryHash,
        ),
      );
    }
    final prevHash = reader.readBytes(32);
    final sealed = reader.readUint8() == 1;
    final outcome = reader.readUint8();
    final abortReason = _readLengthPrefixedUtf8(reader);
    reader.expectEnd();
    return Transcript._(
      ceremonyId: ceremonyId,
      params: params,
      participantIds: participantIds,
      entries: entries,
      prevHash: prevHash,
      sealed: sealed,
      outcome: outcome,
      abortReason: abortReason,
    );
  }

  Uint8List _encodeEntries() {
    final writer = BinaryWriter();
    for (final entry in _entries) {
      writer
        ..writeUint8(entry.round)
        ..writeUint16Be(entry.senderIndex)
        ..writeBytes(entry.messageHash)
        ..writeBytes(entry.prevHash);
    }
    return writer.toBytes();
  }

  Uint8List _computeRootHash() {
    final writer = BinaryWriter()..writeBytes(_encodeEntries());
    writer
      ..writeUint8(_outcome)
      ..writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(_abortReason.codeUnits)]),
      );
    if (_finalPublicKey != null) {
      writer.writeBytes(
        PqBytes.lengthPrefixed([PublicKeyCodec.encode(_finalPublicKey!)]),
      );
    } else {
      writer.writeBytes(PqBytes.lengthPrefixed([Uint8List(0)]));
    }
    return PqBytes.sha256(writer.toBytes());
  }

  static Uint8List _hashEntry({
    required Uint8List prevHash,
    required int round,
    required int senderIndex,
    required Uint8List messageHash,
  }) {
    final writer = BinaryWriter()
      ..writeBytes(prevHash)
      ..writeUint8(round)
      ..writeUint16Be(senderIndex)
      ..writeBytes(messageHash);
    return PqBytes.sha256(writer.toBytes());
  }

  static String _readLengthPrefixedUtf8(BinaryReader reader) {
    return utf8.decode(_readLengthPrefixedBytes(reader));
  }

  static Uint8List _readLengthPrefixedBytes(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}

final class _TranscriptEntry {
  const _TranscriptEntry({
    required this.round,
    required this.senderIndex,
    required this.messageHash,
    required this.prevHash,
    required this.entryHash,
  });

  final int round;
  final int senderIndex;
  final Uint8List messageHash;
  final Uint8List prevHash;
  final Uint8List entryHash;
}
