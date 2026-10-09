/// Per-participant DKG session (`doc/API.md` §4.1).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:swissarmyknife/swissarmyknife.dart';

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../scheme/dkg/dkg_crypto.dart';
import '../scheme/feldman/ed25519_scalar.dart';
import '../scheme/feldman/feldman_vss.dart';
import '../serialization/binary_codec.dart';
import '../sharing/share.dart';
import '../transcript/transcript.dart';
import '../util/ceremony_id.dart';
import 'dkg_message.dart';
import 'dkg_state.dart';

/// Drives one participant through Gennaro DKG rounds (C1).
abstract interface class CeremonySession {
  /// Creates a new session for [participantIndex] in `1..params.n`.
  factory CeremonySession.create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int participantIndex,
    List<String>? participantIds,
  }) => _CeremonySessionImpl(
    params: params,
    ceremonyId: ceremonyId,
    participantId: participantId,
    participantIndex: participantIndex,
    participantIds: participantIds,
  );

  /// Current protocol round (`0` = setup).
  int get round;

  /// Processes peer messages; returns newly generated outbound messages.
  List<DkgMessage> processInbox(Iterable<DkgMessage> inbox);

  /// Whether [finalize] may succeed.
  bool get isComplete;

  /// Participant index bound to this session.
  int get participantIndex;

  /// Final share, joint public key, and sealed transcript.
  ({Share share, PublicKey publicKey, Transcript transcript}) finalize();

  /// Serializes in-progress state for dir-transport CLI (v2).
  Uint8List exportCheckpoint();

  /// Restores a session saved with [exportCheckpoint].
  factory CeremonySession.fromCheckpoint(Uint8List bytes) =>
      _CeremonySessionImpl._fromCheckpoint(bytes);
}

final class _CeremonySessionImpl implements CeremonySession {
  _CeremonySessionImpl({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int participantIndex,
    List<String>? participantIds,
  }) : _params = params,
       _ceremonyId = Uint8List.fromList(ceremonyId),
       _participantId = participantId,
       _participantIndex = participantIndex,
       _machine = _buildMachine(),
       _transcript = Transcript.create(
         ceremonyId: ceremonyId,
         params: params,
         participantIds:
             participantIds ??
             List.generate(params.n, (i) => 'participant-${i + 1}'),
       ) {
    validateCeremonyId(_ceremonyId);
    if (participantIndex < 1 || participantIndex > params.n) {
      throw InvalidParams(
        'participantIndex $participantIndex out of range 1..${params.n}',
      );
    }
    if (participantId.isEmpty) {
      throw InvalidParams('participantId must not be empty');
    }
    if (participantIds != null && participantIds.length != params.n) {
      throw InvalidParams('participantIds length must equal n=${params.n}');
    }
    _bootstrapLocalPolynomial();
  }

  final ThresholdParams _params;
  final Uint8List _ceremonyId;
  final String _participantId;
  final int _participantIndex;
  final StateMachine<DkgState, DkgEvent> _machine;
  final Transcript _transcript;

  List<BigInt> _localCoeffs = [];
  List<Uint8List> _localCommitments = [];
  final Map<int, List<Uint8List>> _round1BySender = {};
  final Map<int, Uint8List> _round2BySender = {};
  Uint8List? _jointPublicKey;
  BigInt? _finalShareScalar;
  String? _abortReason;
  bool _round1Emitted = false;
  bool _round2Emitted = false;
  final Set<String> _recordedMessageKeys = {};

  static StateMachine<DkgState, DkgEvent> _buildMachine() {
    return StateMachine<DkgState, DkgEvent>(
      initialState: DkgState.setup,
      transitions: [
        const StateTransitionRule(
          from: DkgState.setup,
          event: DkgEvent.localPolyReady,
          to: DkgState.round1Broadcast,
        ),
        const StateTransitionRule(
          from: DkgState.round1Broadcast,
          event: DkgEvent.round1Complete,
          to: DkgState.round2Distribute,
        ),
        const StateTransitionRule(
          from: DkgState.round2Distribute,
          event: DkgEvent.round2Complete,
          to: DkgState.finalized,
        ),
        const StateTransitionRule(
          from: DkgState.setup,
          event: DkgEvent.abort,
          to: DkgState.aborted,
        ),
        const StateTransitionRule(
          from: DkgState.round1Broadcast,
          event: DkgEvent.abort,
          to: DkgState.aborted,
        ),
        const StateTransitionRule(
          from: DkgState.round2Distribute,
          event: DkgEvent.abort,
          to: DkgState.aborted,
        ),
        const StateTransitionRule(
          from: DkgState.round3Complaints,
          event: DkgEvent.abort,
          to: DkgState.aborted,
        ),
      ],
    );
  }

  @override
  int get participantIndex => _participantIndex;

  @override
  int get round => dkgStateToRound(_machine.currentState);

  @override
  bool get isComplete => _machine.isIn(DkgState.finalized);

  void _bootstrapLocalPolynomial() {
    final secretContribution = scalarFromLeBytes(PqBytes.randomBytes(32));
    _localCoeffs = FeldmanVss.randomPolynomial(
      secret: secretContribution,
      degree: _params.t - 1,
    );
    _localCommitments = FeldmanVss.commitmentsFromCoefficients(_localCoeffs);
    _machine.trigger(DkgEvent.localPolyReady);
  }

  @override
  List<DkgMessage> processInbox(Iterable<DkgMessage> inbox) {
    if (_machine.isIn(DkgState.aborted)) {
      throw CeremonyAborted(_abortReason ?? 'Ceremony aborted');
    }
    if (_machine.isIn(DkgState.finalized)) {
      return const [];
    }

    final outbox = <DkgMessage>[];

    for (final message in inbox) {
      _ingest(message);
    }

    if (_machine.isIn(DkgState.round1Broadcast)) {
      if (!_round1Emitted) {
        outbox.add(_emitRound1());
        _round1Emitted = true;
      }
      if (_round1BySender.length == _params.n && !_round2Emitted) {
        _advanceRound1Complete();
        outbox.addAll(_emitRound2Shares());
        _round2Emitted = true;
      }
    } else if (_machine.isIn(DkgState.round2Distribute)) {
      if (_round2BySender.length == _params.n) {
        _advanceRound2Complete();
      }
    }

    return outbox;
  }

  void _recordOutbound(DkgMessage message) {
    _appendTranscriptOnce(message);
  }

  void _appendTranscriptOnce(DkgMessage message) {
    final key = PqBytes.sha256(message.wireBytes).join(',');
    if (!_recordedMessageKeys.add(key)) {
      return;
    }
    _transcript.appendRound(
      round: _protocolRoundFor(message),
      senderIndex: message.senderIndex,
      messageBytes: message.wireBytes,
    );
  }

  void _ingest(DkgMessage message) {
    message.assertBinding(params: _params, ceremonyId: _ceremonyId);
    _appendTranscriptOnce(message);

    switch (message.subKind) {
      case DkgWireSubKind.round1:
        _storeRound1(message);
      case DkgWireSubKind.round2:
        _storeRound2(message);
      default:
        throw SerializationError(
          'Unsupported DKG subKind 0x${message.subKind.toRadixString(16)}',
        );
    }
  }

  int _protocolRoundFor(DkgMessage message) => switch (message.subKind) {
    DkgWireSubKind.round1 => 1,
    DkgWireSubKind.round2 => 2,
    _ => 3,
  };

  DkgMessage _emitRound1() {
    _round1BySender[_participantIndex] = _localCommitments;
    final message = DkgMessage.round1(
      params: _params,
      ceremonyId: _ceremonyId,
      senderIndex: _participantIndex,
      commitments: _localCommitments,
    );
    _recordOutbound(message);
    return message;
  }

  void _storeRound1(DkgMessage message) {
    if (_round1BySender.containsKey(message.senderIndex)) {
      return;
    }
    final commitments = DkgMessage.parseRound1Payload(
      message.payload,
      _params.t,
    );
    _round1BySender[message.senderIndex] = commitments;
  }

  void _advanceRound1Complete() {
    final result = _machine.trigger(DkgEvent.round1Complete);
    if (result.isFailure) {
      _abort('Invalid state transition after Round1');
    }
  }

  List<DkgMessage> _emitRound2Shares() {
    final messages = <DkgMessage>[];
    for (var j = 1; j <= _params.n; j++) {
      final shareScalar = evaluatePolynomialAtIndex(_localCoeffs, j);
      final message = DkgMessage.round2(
        params: _params,
        ceremonyId: _ceremonyId,
        senderIndex: _participantIndex,
        recipientIndex: j,
        shareScalarLe: scalarToLeBytes(shareScalar),
      );
      _recordOutbound(message);
      messages.add(message);
    }
    return messages;
  }

  void _storeRound2(DkgMessage message) {
    if (message.recipientIndex != _participantIndex) {
      return;
    }
    if (_round2BySender.containsKey(message.senderIndex)) {
      return;
    }
    final shareScalar = DkgMessage.parseRound2Payload(
      message.payload,
      _participantIndex,
    );
    final senderCommitments = _round1BySender[message.senderIndex];
    if (senderCommitments == null) {
      _abort('Round2 from ${message.senderIndex} before Round1 received');
      return;
    }
    try {
      verifyDkgShare(
        recipientIndex: _participantIndex,
        shareScalarLe: shareScalar,
        senderCommitments: senderCommitments,
      );
    } on InconsistentShares {
      _abort('Share verification failed for sender ${message.senderIndex}');
      return;
    }
    _round2BySender[message.senderIndex] = shareScalar;
  }

  void _advanceRound2Complete() {
    final allCommitments = _sortedCommitmentSets();
    _jointPublicKey = computeJointPublicKey(allCommitments);
    _finalShareScalar = combineShareScalars(
      _round2BySender.values.toList(growable: false),
    );
    final result = _machine.trigger(DkgEvent.round2Complete);
    if (result.isFailure) {
      _abort('Invalid state transition after Round2');
    }
  }

  List<List<Uint8List>> _sortedCommitmentSets() {
    final keys = _round1BySender.keys.toList()..sort();
    return [for (final k in keys) _round1BySender[k]!];
  }

  void _abort(String reason) {
    _abortReason = reason;
    _machine.trigger(DkgEvent.abort);
    _transcript.seal(success: false, abortReason: reason);
    throw CeremonyAborted(reason);
  }

  @override
  ({Share share, PublicKey publicKey, Transcript transcript}) finalize() {
    if (!_machine.isIn(DkgState.finalized)) {
      throw CeremonyAborted('Ceremony not complete (round $round)');
    }
    final pkBytes = _jointPublicKey;
    final shareScalar = _finalShareScalar;
    if (pkBytes == null || shareScalar == null) {
      throw CeremonyAborted('Missing DKG output material');
    }

    final publicKey = PublicKey.create(
      params: _params,
      ceremonyId: _ceremonyId,
      publicKeyBytes: pkBytes,
    );
    final share = Share.create(
      params: _params,
      ceremonyId: _ceremonyId,
      participantId: _participantId,
      index: _participantIndex,
      secretShare: scalarToLeBytes(shareScalar),
      verificationData: Uint8List.fromList(pkBytes),
    );
    _transcript.seal(finalPublicKey: publicKey, success: true);
    return (share: share, publicKey: publicKey, transcript: _transcript);
  }

  @override
  Uint8List exportCheckpoint() {
    final writer = BinaryWriter()
      ..writeBytes(Uint8List.fromList('PQDK'.codeUnits))
      ..writeUint8(1)
      ..writeBytes(_params.toBytes())
      ..writeBytes(_ceremonyId)
      ..writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(_participantId.codeUnits)]),
      )
      ..writeUint16Be(_participantIndex)
      ..writeUint8(_machine.currentState.index)
      ..writeUint8(_round1Emitted ? 1 : 0)
      ..writeUint8(_round2Emitted ? 1 : 0)
      ..writeUint8(_localCoeffs.length)
      ..writeBytes(
        PqBytes.concat([for (final c in _localCoeffs) scalarToLeBytes(c)]),
      )
      ..writeUint8(_round1BySender.length);
    for (final entry in _round1BySender.entries) {
      writer
        ..writeUint16Be(entry.key)
        ..writeBytes(PqBytes.concat(entry.value));
    }
    writer.writeUint8(_round2BySender.length);
    for (final entry in _round2BySender.entries) {
      writer
        ..writeUint16Be(entry.key)
        ..writeBytes(entry.value);
    }
    if (_jointPublicKey != null) {
      writer
        ..writeUint8(1)
        ..writeBytes(_jointPublicKey!);
    } else {
      writer.writeUint8(0);
    }
    if (_finalShareScalar != null) {
      writer
        ..writeUint8(1)
        ..writeBytes(scalarToLeBytes(_finalShareScalar!));
    } else {
      writer.writeUint8(0);
    }
    if (_abortReason != null) {
      writer.writeBytes(
        PqBytes.lengthPrefixed([Uint8List.fromList(_abortReason!.codeUnits)]),
      );
    } else {
      writer.writeBytes(PqBytes.lengthPrefixed([Uint8List(0)]));
    }
    writer.writeBytes(_transcript.exportWorkingCheckpoint());
    return writer.toBytes();
  }

  static _CeremonySessionImpl _fromCheckpoint(Uint8List bytes) {
    final reader = BinaryReader(bytes);
    final magic = String.fromCharCodes(reader.readBytes(4));
    if (magic != 'PQDK') {
      throw SerializationError('Invalid DKG checkpoint magic');
    }
    final version = reader.readUint8();
    if (version != 1) {
      throw SerializationError('Unsupported DKG checkpoint version: $version');
    }
    final params = ThresholdParams.fromBytes(reader.readBytes(16));
    final ceremonyId = reader.readBytes(16);
    final participantId = String.fromCharCodes(_readLp(reader));
    final participantIndex = reader.readUint16Be();
    final stateIndex = reader.readUint8();
    final round1Emitted = reader.readUint8() == 1;
    final round2Emitted = reader.readUint8() == 1;
    final coeffCount = reader.readUint8();
    final coeffs = <BigInt>[
      for (var i = 0; i < coeffCount; i++)
        scalarFromLeBytes(reader.readBytes(32)),
    ];
    final round1Count = reader.readUint8();
    final round1BySender = <int, List<Uint8List>>{};
    for (var i = 0; i < round1Count; i++) {
      final sender = reader.readUint16Be();
      round1BySender[sender] = [
        for (var j = 0; j < params.t; j++) reader.readBytes(32),
      ];
    }
    final round2Count = reader.readUint8();
    final round2BySender = <int, Uint8List>{};
    for (var i = 0; i < round2Count; i++) {
      final sender = reader.readUint16Be();
      round2BySender[sender] = reader.readBytes(32);
    }
    Uint8List? jointPk;
    if (reader.readUint8() == 1) {
      jointPk = reader.readBytes(32);
    }
    BigInt? finalShare;
    if (reader.readUint8() == 1) {
      finalShare = scalarFromLeBytes(reader.readBytes(32));
    }
    final abortText = _readLp(reader);
    final abortReason = abortText.isEmpty
        ? null
        : String.fromCharCodes(abortText);
    final transcriptBytes = reader.readBytes(reader.remaining);
    final transcript = Transcript.fromWorkingCheckpoint(transcriptBytes);

    final session = _CeremonySessionImpl._restore(
      params: params,
      ceremonyId: ceremonyId,
      participantId: participantId,
      participantIndex: participantIndex,
      machineState: DkgState.values[stateIndex],
      round1Emitted: round1Emitted,
      round2Emitted: round2Emitted,
      localCoeffs: coeffs,
      round1BySender: round1BySender,
      round2BySender: round2BySender,
      jointPublicKey: jointPk,
      finalShareScalar: finalShare,
      abortReason: abortReason,
      transcript: transcript,
    );
    return session;
  }

  _CeremonySessionImpl._restore({
    required this._params,
    required Uint8List ceremonyId,
    required this._participantId,
    required this._participantIndex,
    required DkgState machineState,
    required bool round1Emitted,
    required bool round2Emitted,
    required List<BigInt> localCoeffs,
    required Map<int, List<Uint8List>> round1BySender,
    required Map<int, Uint8List> round2BySender,
    Uint8List? jointPublicKey,
    BigInt? finalShareScalar,
    String? abortReason,
    required this._transcript,
  }) : _ceremonyId = Uint8List.fromList(ceremonyId),
       _machine = _buildMachine() {
    _machine.reset(machineState, clearHistory: true);
    _localCoeffs = localCoeffs;
    _localCommitments = FeldmanVss.commitmentsFromCoefficients(localCoeffs);
    _round1BySender.addAll(round1BySender);
    _round2BySender.addAll(round2BySender);
    _jointPublicKey = jointPublicKey;
    _finalShareScalar = finalShareScalar;
    _abortReason = abortReason;
    _round1Emitted = round1Emitted;
    _round2Emitted = round2Emitted;
  }

  static Uint8List _readLp(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }
}
