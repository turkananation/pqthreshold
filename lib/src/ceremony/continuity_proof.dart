/// C5 rotation continuity evidence (`doc/SERIALIZATION.md` §4.6).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart' hide PublicKey;

import '../errors/threshold_exception.dart';
import '../serialization/continuity_proof_codec.dart';
import '../sharing/share.dart';
import '../signing/threshold_signer.dart';
import '../util/ceremony_id.dart';
import 'continuity_payload.dart';

/// Links a new threshold public key to an authorized predecessor.
final class ContinuityProof {
  ContinuityProof._({
    required this.oldCeremonyId,
    required this.newCeremonyId,
    required this.oldPublicKeyBytes,
    required this.newPublicKeyBytes,
    required this.signedAtUnixSeconds,
    required this.thresholdSignature,
  });

  /// Prior root ceremony identifier (16 bytes).
  final Uint8List oldCeremonyId;

  /// Successor root ceremony identifier (16 bytes).
  final Uint8List newCeremonyId;

  /// 32-byte Ed25519 encoding of the old joint key.
  final Uint8List oldPublicKeyBytes;

  /// 32-byte Ed25519 encoding of the new joint key.
  final Uint8List newPublicKeyBytes;

  /// Unix seconds when the old quorum authorized rotation.
  final int signedAtUnixSeconds;

  /// Threshold Ed25519 signature over [continuityPayloadBytes].
  final Uint8List thresholdSignature;

  /// Canonical serialized bytes (`doc/SERIALIZATION.md` §4.6).
  Uint8List toBytes() => ContinuityProofCodec.encode(this);

  /// Parses a continuity proof.
  factory ContinuityProof.fromBytes(Uint8List bytes) =>
      ContinuityProofCodec.decode(bytes);

  /// Constructs a proof after the old quorum has threshold-signed the payload.
  @internal
  factory ContinuityProof.create({
    required Uint8List oldCeremonyId,
    required Uint8List newCeremonyId,
    required Uint8List oldPublicKeyBytes,
    required Uint8List newPublicKeyBytes,
    required int signedAtUnixSeconds,
    required Uint8List thresholdSignature,
  }) {
    validateCeremonyId(oldCeremonyId);
    validateCeremonyId(newCeremonyId);
    if (oldPublicKeyBytes.length != 32 || newPublicKeyBytes.length != 32) {
      throw InvalidParams('ContinuityProof public keys must be 32 bytes');
    }
    if (thresholdSignature.length != 64) {
      throw SerializationError('ContinuityProof signature must be 64 bytes');
    }
    RangeError.checkNotNegative(signedAtUnixSeconds, 'signedAtUnixSeconds');
    return ContinuityProof._(
      oldCeremonyId: Uint8List.fromList(oldCeremonyId),
      newCeremonyId: Uint8List.fromList(newCeremonyId),
      oldPublicKeyBytes: Uint8List.fromList(oldPublicKeyBytes),
      newPublicKeyBytes: Uint8List.fromList(newPublicKeyBytes),
      signedAtUnixSeconds: signedAtUnixSeconds,
      thresholdSignature: Uint8List.fromList(thresholdSignature),
    );
  }

  /// Signed payload bytes (`doc/PROTOCOL_MESSAGES.md` §6).
  Uint8List continuityPayloadBytes() => buildContinuityPayload(
        oldPublicKeyBytes: oldPublicKeyBytes,
        newPublicKeyBytes: newPublicKeyBytes,
        signedAtUnixSeconds: signedAtUnixSeconds,
        oldCeremonyId: oldCeremonyId,
        newCeremonyId: newCeremonyId,
      );

  /// Verifies [thresholdSignature] under [oldPublicKey].
  Future<bool> verify({required PublicKey oldPublicKey}) {
    if (!PqBytes.constantTimeEquals(oldPublicKey.ceremonyId, oldCeremonyId)) {
      return Future.value(false);
    }
    if (!PqBytes.constantTimeEquals(oldPublicKey.bytes, oldPublicKeyBytes)) {
      return Future.value(false);
    }
    return ThresholdSigner.verify(
      publicKey: oldPublicKey,
      message: continuityPayloadBytes(),
      signature: thresholdSignature,
    );
  }
}
