/// Two-round FROST signing session with local checkpoint (`doc/PROTOCOL_MESSAGES.md` §5).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/threshold_params.dart';
import '../scheme/feldman/ed25519_scalar.dart';
import '../scheme/frost/frost_identifier.dart';
import '../scheme/frost/frost_signing.dart';
import '../serialization/binary_codec.dart';
import '../sharing/share.dart';
import '../util/secret_buffer.dart';
import 'frost_signing_message.dart';
import 'partial_signature.dart';

/// Officer-local signing state between FROST Round1 and Round2.
///
/// Checkpoint bytes contain ephemeral nonces — **never** publish or relay.
final class SigningSession {
  SigningSession._({
    required this.params,
    required this.ceremonyId,
    required this.signerIndex,
    required this.message,
    required this.context,
    required this.messageBinding,
    required this.publicKeyFingerprint,
    required this._hidingNonce,
    required this._bindingNonce,
    required this._secretShare,
  });

  /// Threshold parameters for this ceremony.
  final ThresholdParams params;

  /// Ceremony identifier.
  final Uint8List ceremonyId;

  /// 1-based signer index.
  final int signerIndex;

  /// Message being signed.
  final Uint8List message;

  /// Optional application context for message binding.
  final Uint8List context;

  /// Precomputed message binding hash.
  final Uint8List messageBinding;

  /// Joint public key fingerprint.
  final Uint8List publicKeyFingerprint;

  final SecretBuffer _hidingNonce;
  final SecretBuffer _bindingNonce;
  final SecretBuffer _secretShare;

  /// Starts Round1: returns wire message and local session for Round2.
  static Future<({FrostSigningMessage round1, SigningSession session})> begin({
    required Share share,
    required Uint8List message,
    Uint8List? context,
  }) async {
    final publicKey = _jointPublicKeyFromShare(share);
    final ctx = context ?? Uint8List(0);
    final binding = messageBindingFor(
      publicKey: publicKey,
      message: message,
      context: context,
    );
    final frostId = buildFrostIdentifier(
      ceremonyId: share.ceremonyId,
      params: share.params,
    );
    final secretShare = scalarFromLeBytes(share.secretShareBytes());
    final nonces = FrostSigning.generateNonces(
      frostIdentifier: frostId,
      secretShare: secretShare,
    );
    final commitment = FrostSigning.commitmentsFromNonces(
      index: share.index,
      nonces: nonces,
    );
    final round1 = FrostSigningMessage.round1(
      params: share.params,
      ceremonyId: share.ceremonyId,
      senderIndex: share.index,
      messageBinding: binding,
      hidingCommitment: commitment.hiding,
      bindingCommitment: commitment.binding,
    );
    final session = SigningSession._(
      params: share.params,
      ceremonyId: Uint8List.fromList(share.ceremonyId),
      signerIndex: share.index,
      message: Uint8List.fromList(message),
      context: Uint8List.fromList(ctx),
      messageBinding: binding,
      publicKeyFingerprint: Uint8List.fromList(publicKey.fingerprint),
      hidingNonce: SecretBuffer(scalarToLeBytes(nonces.hiding)),
      bindingNonce: SecretBuffer(scalarToLeBytes(nonces.binding)),
      secretShare: SecretBuffer(share.secretShareBytes()),
    );
    return (round1: round1, session: session);
  }

  /// Completes Round2 after collecting ≥ t Round1 wire messages (including own).
  PartialSignature completeRound2({
    required Iterable<FrostSigningMessage> round1Messages,
    required PublicKey publicKey,
  }) {
    if (!PqBytes.constantTimeEquals(ceremonyId, publicKey.ceremonyId)) {
      throw WrongCeremony('PublicKey ceremonyId mismatch');
    }
    final expectedBinding = messageBindingFor(
      publicKey: publicKey,
      message: message,
      context: context.isEmpty ? null : context,
    );
    if (!PqBytes.constantTimeEquals(messageBinding, expectedBinding)) {
      throw InvalidPartialSignature('SigningSession message binding mismatch');
    }

    final frostId = buildFrostIdentifier(
      ceremonyId: ceremonyId,
      params: params,
    );

    final commitments = <FrostCommitment>[];
    final seen = <int>{};
    for (final wire in round1Messages) {
      wire.assertBinding(params: params, ceremonyId: ceremonyId);
      if (wire.subKind != FrostWireSubKind.round1) {
        throw SerializationError('Expected FROST Round1 message');
      }
      final parsed = FrostSigningMessage.parseRound1Payload(wire.payload);
      if (!PqBytes.constantTimeEquals(parsed.messageBinding, messageBinding)) {
        throw InvalidPartialSignature('Round1 messageBinding mismatch');
      }
      if (!seen.add(wire.senderIndex)) {
        throw InvalidPartialSignature(
          'Duplicate Round1 sender ${wire.senderIndex}',
        );
      }
      commitments.add(
        FrostCommitment(
          index: wire.senderIndex,
          hiding: parsed.hidingCommitment,
          binding: parsed.bindingCommitment,
        ),
      );
    }

    if (commitments.length < params.t) {
      throw InvalidPartialSignature(
        'Need at least ${params.t} Round1 messages, got ${commitments.length}',
      );
    }

    final selected = [...commitments]
      ..sort((a, b) => a.index.compareTo(b.index));
    final signerIndices = selected.take(params.t).map((c) => c.index).toList();
    if (!signerIndices.contains(signerIndex)) {
      throw InvalidPartialSignature(
        'This session index $signerIndex not in selected signer set',
      );
    }

    final bindingFactors = FrostSigning.computeBindingFactors(
      frostIdentifier: frostId,
      groupPublicKey: publicKey.bytes,
      message: message,
      commitments: selected.take(params.t).toList(),
    );
    final groupCommitment = FrostSigning.computeGroupCommitment(
      commitments: selected.take(params.t).toList(),
      bindingFactors: bindingFactors,
    );
    final challenge = FrostSigning.computeChallenge(
      frostIdentifier: frostId,
      groupCommitment: groupCommitment,
      groupPublicKey: publicKey.bytes,
      message: message,
    );

    final sk = scalarFromLeBytes(_secretShare.bytes);
    final nonces = FrostNonces(
      hiding: scalarFromLeBytes(_hidingNonce.bytes),
      binding: scalarFromLeBytes(_bindingNonce.bytes),
    );
    final z = FrostSigning.computeSignatureShare(
      signerIndex: signerIndex,
      secretShare: sk,
      nonces: nonces,
      bindingFactor: bindingFactors[signerIndex]!,
      challenge: challenge,
      signerIndices: signerIndices,
    );

    final ownCommitment = selected.firstWhere((c) => c.index == signerIndex);
    return PartialSignature.createFromCodec(
      ceremonyId: ceremonyId,
      publicKeyFingerprint: publicKeyFingerprint,
      signerIndex: signerIndex,
      messageBinding: messageBinding,
      hidingCommitment: ownCommitment.hiding,
      bindingCommitment: ownCommitment.binding,
      partialScalar: scalarToLeBytes(z),
    );
  }

  /// Encodes officer-local checkpoint (contains secrets).
  Uint8List toCheckpoint() {
    final writer = BinaryWriter()
      ..writeBytes(params.toBytes())
      ..writeBytes(ceremonyId)
      ..writeUint16Be(signerIndex)
      ..writeBytes(PqBytes.lengthPrefixed([message]))
      ..writeBytes(PqBytes.lengthPrefixed([context]))
      ..writeBytes(messageBinding)
      ..writeBytes(publicKeyFingerprint)
      ..writeBytes(_hidingNonce.bytes)
      ..writeBytes(_bindingNonce.bytes)
      ..writeBytes(_secretShare.bytes);
    return writer.toBytes();
  }

  /// Restores a session from [toCheckpoint] bytes.
  factory SigningSession.fromCheckpoint(Uint8List bytes) {
    final reader = BinaryReader(bytes);
    final params = ThresholdParams.fromBytes(reader.readBytes(16));
    final ceremonyId = reader.readBytes(16);
    final signerIndex = reader.readUint16Be();
    final message = _readLengthPrefixed(reader);
    final context = _readLengthPrefixed(reader);
    final messageBinding = reader.readBytes(32);
    final fingerprint = reader.readBytes(32);
    final hiding = reader.readBytes(32);
    final binding = reader.readBytes(32);
    final share = reader.readBytes(32);
    reader.expectEnd();
    return SigningSession._(
      params: params,
      ceremonyId: ceremonyId,
      signerIndex: signerIndex,
      message: message,
      context: context,
      messageBinding: messageBinding,
      publicKeyFingerprint: fingerprint,
      hidingNonce: SecretBuffer(hiding),
      bindingNonce: SecretBuffer(binding),
      secretShare: SecretBuffer(share),
    );
  }

  /// Wipes ephemeral material held in memory.
  void dispose() {
    _hidingNonce.dispose();
    _bindingNonce.dispose();
    _secretShare.dispose();
  }

  static Uint8List _readLengthPrefixed(BinaryReader reader) {
    final length = reader.readUint32Be();
    return reader.readBytes(length);
  }

  static PublicKey _jointPublicKeyFromShare(Share share) {
    if (share.verificationData.length != 32) {
      throw InvalidParams(
        'Share verificationData must contain 32-byte joint public key',
      );
    }
    return PublicKey.create(
      params: share.params,
      ceremonyId: share.ceremonyId,
      publicKeyBytes: share.verificationData,
    );
  }
}

/// Builds combine-ready partials from Round1 + Round2 wire messages.
List<PartialSignature> partialsFromRound2Messages({
  required Iterable<FrostSigningMessage> round1Messages,
  required Iterable<FrostSigningMessage> round2Messages,
  required PublicKey publicKey,
}) {
  final round1BySender = <int, FrostCommitment>{};
  for (final msg in round1Messages) {
    if (msg.subKind != FrostWireSubKind.round1) continue;
    final parsed = FrostSigningMessage.parseRound1Payload(msg.payload);
    round1BySender[msg.senderIndex] = FrostCommitment(
      index: msg.senderIndex,
      hiding: parsed.hidingCommitment,
      binding: parsed.bindingCommitment,
    );
  }

  final partials = <PartialSignature>[];
  for (final msg in round2Messages) {
    msg.assertBinding(
      params: publicKey.params,
      ceremonyId: publicKey.ceremonyId,
    );
    if (msg.subKind != FrostWireSubKind.round2) {
      throw SerializationError('Expected FROST Round2 message');
    }
    final parsed = FrostSigningMessage.parseRound2Payload(msg.payload);
    final commitment = round1BySender[msg.senderIndex];
    if (commitment == null) {
      throw InvalidPartialSignature(
        'Missing Round1 commitment for signer ${msg.senderIndex}',
      );
    }
    partials.add(
      PartialSignature.createFromCodec(
        ceremonyId: publicKey.ceremonyId,
        publicKeyFingerprint: publicKey.fingerprint,
        signerIndex: msg.senderIndex,
        messageBinding: parsed.messageBinding,
        hidingCommitment: commitment.hiding,
        bindingCommitment: commitment.binding,
        partialScalar: parsed.partialScalarLe,
      ),
    );
  }
  partials.sort((a, b) => a.signerIndex.compareTo(b.signerIndex));
  if (partials.length > publicKey.params.t) {
    return partials.take(publicKey.params.t).toList();
  }
  return partials;
}

/// Encodes Round2 wire message from a completed partial.
FrostSigningMessage frostRound2WireFromPartial({
  required PartialSignature partial,
  required ThresholdParams params,
}) {
  return FrostSigningMessage.round2(
    params: params,
    ceremonyId: partial.ceremonyId,
    senderIndex: partial.signerIndex,
    messageBinding: partial.messageBinding,
    partialScalarLe: partial.partialScalar,
  );
}
