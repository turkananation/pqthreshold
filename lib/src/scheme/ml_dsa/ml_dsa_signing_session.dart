/// Three-round ML-DSA threshold signing session with officer-local checkpoint.
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/scheme_id.dart';
import '../../params/threshold_params.dart';
import '../../serialization/binary_codec.dart';
import '../../util/secret_buffer.dart';
import 'ml_dsa_domain.dart';
import 'ml_dsa_share.dart';
import 'ml_dsa_signing_message.dart';
import 'mithril_bridge.dart';

/// Officer-local ML-DSA signing state between distributed wire rounds.
///
/// Checkpoints contain the ceremony seed — **never** publish or relay.
final class MlDsaSigningSession {
  MlDsaSigningSession._({
    required this.params,
    required this.ceremonyId,
    required this.signerIndex,
    required this.message,
    required this.sessionId,
    required this.activePartyIdsZeroBased,
    required this.publicKeyFingerprint,
    required this._ceremonySeed,
  });

  final ThresholdParams params;
  final Uint8List ceremonyId;
  final int signerIndex;
  final Uint8List message;
  final Uint8List sessionId;
  final List<int> activePartyIdsZeroBased;
  final Uint8List publicKeyFingerprint;
  final SecretBuffer _ceremonySeed;

  /// Starts Round1 for [share] against [publicKey] and [activePartyIdsZeroBased].
  static Future<({MlDsaSigningMessage round1, MlDsaSigningSession session})>
  begin({
    required MlDsaShare share,
    required Uint8List message,
    required MlDsaPublicKey publicKey,
    required List<int> activePartyIdsZeroBased,
    String? mithrilBridgePath,
  }) async {
    if (paramsSchemeMismatch(share, publicKey)) {
      throw WrongCeremony('Share/publicKey ceremony mismatch');
    }
    if (share.params.scheme != SchemeId.mlDsa44ThresholdV1) {
      throw SchemeNotImplemented(
        'Distributed ML-DSA supports mlDsa44ThresholdV1',
      );
    }
    final active = [...activePartyIdsZeroBased]..sort();
    if (active.length < share.params.t) {
      throw InvalidParams(
        'active set must have at least t=${share.params.t} parties',
      );
    }
    if (!active.contains(share.mithrilPartyId)) {
      throw InvalidParams(
        'Share party ${share.mithrilPartyId} not in active set',
      );
    }

    final binding = mlDsaMessageBinding(
      ceremonyId: share.ceremonyId,
      jointPublicKey: publicKey.bytes,
      message: message,
    );
    final sessionId = await mithrilDeriveSessionId(
      t: share.params.t,
      n: share.params.n,
      publicKey: publicKey.bytes,
      activePartyIdsZeroBased: active,
      message: message,
      binding: binding,
      executablePath: mithrilBridgePath,
    );
    final hash = await mithrilRound1Party(
      t: share.params.t,
      n: share.params.n,
      ceremonySeed: share.ceremonySeedBytes(),
      partyIdZeroBased: share.mithrilPartyId,
      activePartyIdsZeroBased: active,
      message: message,
      sessionId: sessionId,
      executablePath: mithrilBridgePath,
    );
    final round1 = MlDsaSigningMessage.round1(
      params: share.params,
      ceremonyId: share.ceremonyId,
      senderIndex: share.index,
      sessionId: sessionId,
      commitmentHash: hash,
    );
    final session = MlDsaSigningSession._(
      params: share.params,
      ceremonyId: Uint8List.fromList(share.ceremonyId),
      signerIndex: share.index,
      message: Uint8List.fromList(message),
      sessionId: Uint8List.fromList(sessionId),
      activePartyIdsZeroBased: active,
      publicKeyFingerprint: Uint8List.fromList(publicKey.fingerprint),
      ceremonySeed: SecretBuffer(share.ceremonySeedBytes()),
    );
    return (round1: round1, session: session);
  }

  /// Completes Round2 after collecting Round1 wire messages for all [activePartyIdsZeroBased].
  Future<MlDsaSigningMessage> completeRound2({
    required Iterable<MlDsaSigningMessage> round1Messages,
  }) async {
    _assertRound1Messages(round1Messages);
    final hashes = _orderedRound1Hashes(round1Messages);
    final reveal = await mithrilRound2Party(
      t: params.t,
      n: params.n,
      ceremonySeed: _ceremonySeed.bytes,
      partyIdZeroBased: signerIndex - 1,
      activePartyIdsZeroBased: activePartyIdsZeroBased,
      message: message,
      sessionId: sessionId,
      round1Hashes: hashes,
    );
    return MlDsaSigningMessage.round2(
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: signerIndex,
      sessionId: sessionId,
      revealBytes: reveal,
    );
  }

  /// Completes Round3 after collecting Round1 + Round2 wire messages.
  Future<MlDsaSigningMessage> completeRound3({
    required Iterable<MlDsaSigningMessage> round1Messages,
    required Iterable<MlDsaSigningMessage> round2Messages,
  }) async {
    _assertRound1Messages(round1Messages);
    _assertRound2Messages(round2Messages);
    final hashes = _orderedRound1Hashes(round1Messages);
    final reveals = _orderedRound2Reveals(round2Messages);
    final wfinals = await mithrilAggregateWfinals(
      t: params.t,
      n: params.n,
      round2Reveals: reveals,
    );
    final response = await mithrilRound3Party(
      t: params.t,
      n: params.n,
      ceremonySeed: _ceremonySeed.bytes,
      partyIdZeroBased: signerIndex - 1,
      activePartyIdsZeroBased: activePartyIdsZeroBased,
      message: message,
      sessionId: sessionId,
      round1Hashes: hashes,
      round2Reveals: reveals,
      wfinals: wfinals,
    );
    return MlDsaSigningMessage.round3(
      params: params,
      ceremonyId: ceremonyId,
      senderIndex: signerIndex,
      sessionId: sessionId,
      responseBytes: response,
    );
  }

  Uint8List toCheckpoint() {
    final writer = BinaryWriter()
      ..writeBytes(params.toBytes())
      ..writeBytes(ceremonyId)
      ..writeUint16Be(signerIndex)
      ..writeBytes(PqBytes.lengthPrefixed([message]))
      ..writeBytes(sessionId)
      ..writeUint16Be(activePartyIdsZeroBased.length);
    for (final id in activePartyIdsZeroBased) {
      writer.writeUint8(id);
    }
    writer
      ..writeBytes(publicKeyFingerprint)
      ..writeBytes(_ceremonySeed.bytes);
    return writer.toBytes();
  }

  factory MlDsaSigningSession.fromCheckpoint(Uint8List bytes) {
    final reader = BinaryReader(bytes);
    final params = ThresholdParams.fromBytes(reader.readBytes(16));
    final ceremonyId = reader.readBytes(16);
    final signerIndex = reader.readUint16Be();
    final messageLen = reader.readUint32Be();
    final message = reader.readBytes(messageLen);
    final sessionId = reader.readBytes(32);
    final activeLen = reader.readUint16Be();
    final active = <int>[];
    for (var i = 0; i < activeLen; i++) {
      active.add(reader.readUint8());
    }
    final fingerprint = reader.readBytes(32);
    final seed = reader.readBytes(32);
    reader.expectEnd();
    return MlDsaSigningSession._(
      params: params,
      ceremonyId: ceremonyId,
      signerIndex: signerIndex,
      message: message,
      sessionId: sessionId,
      activePartyIdsZeroBased: active,
      publicKeyFingerprint: fingerprint,
      ceremonySeed: SecretBuffer(seed),
    );
  }

  void dispose() => _ceremonySeed.dispose();

  void _assertRound1Messages(Iterable<MlDsaSigningMessage> messages) {
    final seen = <int>{};
    for (final wire in messages) {
      _assertWire(wire, MlDsaWireKind.round1, MlDsaWireSubKind.round1Commit);
      if (wire.payload.length != 32) {
        throw InvalidPartialSignature('Round1 hash must be 32 bytes');
      }
      if (!seen.add(wire.senderIndex)) {
        throw InvalidPartialSignature(
          'Duplicate Round1 sender ${wire.senderIndex}',
        );
      }
    }
    if (seen.length != activePartyIdsZeroBased.length) {
      throw InvalidPartialSignature(
        'Need ${activePartyIdsZeroBased.length} Round1 messages, got ${seen.length}',
      );
    }
    for (final id in activePartyIdsZeroBased) {
      if (!seen.contains(id + 1)) {
        throw InvalidPartialSignature('Missing Round1 from party ${id + 1}');
      }
    }
  }

  void _assertRound2Messages(Iterable<MlDsaSigningMessage> messages) {
    final seen = <int>{};
    for (final wire in messages) {
      _assertWire(wire, MlDsaWireKind.round2, MlDsaWireSubKind.round2Reveal);
      if (!seen.add(wire.senderIndex)) {
        throw InvalidPartialSignature(
          'Duplicate Round2 sender ${wire.senderIndex}',
        );
      }
    }
    if (seen.length != activePartyIdsZeroBased.length) {
      throw InvalidPartialSignature(
        'Need ${activePartyIdsZeroBased.length} Round2 messages, got ${seen.length}',
      );
    }
  }

  void _assertWire(MlDsaSigningMessage wire, int kind, int subKind) {
    if (!PqBytes.constantTimeEquals(wire.ceremonyId, ceremonyId)) {
      throw WrongCeremony('Wire ceremonyId mismatch');
    }
    if (!PqBytes.constantTimeEquals(wire.sessionId, sessionId)) {
      throw InvalidPartialSignature('Wire sessionId mismatch');
    }
    if (wire.kind != kind || wire.subKind != subKind) {
      throw SerializationError('Unexpected ML-DSA wire kind/subKind');
    }
    if (wire.scheme != params.scheme) {
      throw WrongCeremony('Wire scheme mismatch');
    }
  }

  List<Uint8List> _orderedRound1Hashes(Iterable<MlDsaSigningMessage> messages) {
    final bySender = {for (final m in messages) m.senderIndex: m.payload};
    return [
      for (final id in activePartyIdsZeroBased)
        bySender[id + 1] ??
            (throw InvalidPartialSignature('missing round1 $id')),
    ];
  }

  List<Uint8List> _orderedRound2Reveals(
    Iterable<MlDsaSigningMessage> messages,
  ) {
    final bySender = {for (final m in messages) m.senderIndex: m.payload};
    return [
      for (final id in activePartyIdsZeroBased)
        bySender[id + 1] ??
            (throw InvalidPartialSignature('missing round2 $id')),
    ];
  }

  static bool paramsSchemeMismatch(MlDsaShare share, MlDsaPublicKey publicKey) {
    return share.params != publicKey.params ||
        !PqBytes.constantTimeEquals(share.ceremonyId, publicKey.ceremonyId);
  }
}

/// Combines Round2 + Round3 wire dirs into an ML-DSA signature.
Future<Uint8List> combineMlDsaFromWire({
  required MlDsaPublicKey publicKey,
  required Uint8List message,
  required Iterable<MlDsaSigningMessage> round2Messages,
  required Iterable<MlDsaSigningMessage> round3Messages,
  required List<int> activePartyIdsZeroBased,
  String? mithrilBridgePath,
}) async {
  final active = [...activePartyIdsZeroBased]..sort();
  final reveals = _orderedPayloads(
    round2Messages,
    active,
    MlDsaWireKind.round2,
  );
  final responses = _orderedPayloads(
    round3Messages,
    active,
    MlDsaWireKind.round3,
  );
  final wfinals = await mithrilAggregateWfinals(
    t: publicKey.params.t,
    n: publicKey.params.n,
    round2Reveals: reveals,
    executablePath: mithrilBridgePath,
  );
  return mithrilCombineWire(
    t: publicKey.params.t,
    n: publicKey.params.n,
    publicKey: publicKey.bytes,
    message: message,
    wfinals: wfinals,
    round3Responses: responses,
    executablePath: mithrilBridgePath,
  );
}

List<Uint8List> _orderedPayloads(
  Iterable<MlDsaSigningMessage> messages,
  List<int> active,
  int kind,
) {
  final bySender = <int, Uint8List>{};
  for (final m in messages) {
    if (m.kind != kind) continue;
    bySender[m.senderIndex] = m.payload;
  }
  return [
    for (final id in active)
      bySender[id + 1] ??
          (throw InvalidPartialSignature(
            'missing wire message for party ${id + 1}',
          )),
  ];
}
