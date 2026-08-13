/// Threshold partial signature material (`doc/API.md` §3.4).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../scheme/feldman/ed25519_scalar.dart';
import '../serialization/partial_signature_codec.dart';
import '../util/secret_buffer.dart';

/// One signer's FROST round material for a single message.
final class PartialSignature {
  PartialSignature._({
    required this.ceremonyId,
    required this.publicKeyFingerprint,
    required this.signerIndex,
    required this.messageBinding,
    required this.hidingCommitment,
    required this.bindingCommitment,
    required this.partialScalar,
    this._hidingNonce,
    this._bindingNonce,
    this._secretShare,
  });

  /// Ceremony identifier.
  final Uint8List ceremonyId;

  /// SHA-256 fingerprint of joint [PublicKey] canonical bytes.
  final Uint8List publicKeyFingerprint;

  /// 1-based signer index.
  final int signerIndex;

  /// Message binding hash.
  final Uint8List messageBinding;

  /// Round1 hiding commitment (32 bytes).
  final Uint8List hidingCommitment;

  /// Round1 binding commitment (32 bytes).
  final Uint8List bindingCommitment;

  /// Round2 partial scalar **z_i**.
  final Uint8List partialScalar;

  final SecretBuffer? _hidingNonce;
  final SecretBuffer? _bindingNonce;
  final SecretBuffer? _secretShare;

  /// Canonical serialized bytes (`doc/SERIALIZATION.md` §4.4).
  Uint8List toBytes() => PartialSignatureCodec.encode(this);

  /// Parses a partial signature.
  factory PartialSignature.fromBytes(Uint8List bytes) =>
      PartialSignatureCodec.decode(bytes);

  /// Whether ephemeral nonces are still held for local combine.
  @internal
  bool get hasEphemeralNonces =>
      _hidingNonce != null && _bindingNonce != null && _secretShare != null;

  @internal
  BigInt? hidingNonceScalar() {
    final nonce = _hidingNonce;
    return nonce == null ? null : scalarFromLeBytes(nonce.bytes);
  }

  @internal
  BigInt? bindingNonceScalar() {
    final nonce = _bindingNonce;
    return nonce == null ? null : scalarFromLeBytes(nonce.bytes);
  }

  @internal
  void disposeEphemeralNonces() {
    _hidingNonce?.dispose();
    _bindingNonce?.dispose();
    _secretShare?.dispose();
  }

  @internal
  BigInt? secretShareScalar() {
    final share = _secretShare;
    return share == null ? null : scalarFromLeBytes(share.bytes);
  }

  /// Internal construction during signing.
  @internal
  factory PartialSignature.create({
    required Uint8List ceremonyId,
    required Uint8List publicKeyFingerprint,
    required int signerIndex,
    required Uint8List messageBinding,
    required Uint8List hidingCommitment,
    required Uint8List bindingCommitment,
    Uint8List? partialScalar,
    Uint8List? hidingNonce,
    Uint8List? bindingNonce,
    Uint8List? secretShare,
  }) {
    if (signerIndex < 1) {
      throw InvalidParams('signerIndex must be >= 1');
    }
    _assertPoint(hidingCommitment, 'hidingCommitment');
    _assertPoint(bindingCommitment, 'bindingCommitment');
    if (publicKeyFingerprint.length != 32) {
      throw InvalidParams('publicKeyFingerprint must be 32 bytes');
    }
    return PartialSignature._(
      ceremonyId: Uint8List.fromList(ceremonyId),
      publicKeyFingerprint: Uint8List.fromList(publicKeyFingerprint),
      signerIndex: signerIndex,
      messageBinding: Uint8List.fromList(messageBinding),
      hidingCommitment: Uint8List.fromList(hidingCommitment),
      bindingCommitment: Uint8List.fromList(bindingCommitment),
      partialScalar: partialScalar == null
          ? Uint8List(32)
          : Uint8List.fromList(partialScalar),
      hidingNonce: hidingNonce == null
          ? null
          : SecretBuffer(Uint8List.fromList(hidingNonce)),
      bindingNonce: bindingNonce == null
          ? null
          : SecretBuffer(Uint8List.fromList(bindingNonce)),
      secretShare: secretShare == null
          ? null
          : SecretBuffer(Uint8List.fromList(secretShare)),
    );
  }

  @internal
  factory PartialSignature.createFromCodec({
    required Uint8List ceremonyId,
    required Uint8List publicKeyFingerprint,
    required int signerIndex,
    required Uint8List messageBinding,
    required Uint8List hidingCommitment,
    required Uint8List bindingCommitment,
    required Uint8List partialScalar,
  }) {
    return PartialSignature._(
      ceremonyId: ceremonyId,
      publicKeyFingerprint: publicKeyFingerprint,
      signerIndex: signerIndex,
      messageBinding: messageBinding,
      hidingCommitment: hidingCommitment,
      bindingCommitment: bindingCommitment,
      partialScalar: partialScalar,
    );
  }

  static void _assertPoint(Uint8List bytes, String label) {
    if (bytes.length != 32) {
      throw InvalidParams('$label must be 32 bytes');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is PartialSignature &&
        PqBytes.constantTimeEquals(other.ceremonyId, ceremonyId) &&
        other.signerIndex == signerIndex &&
        PqBytes.constantTimeEquals(other.toBytes(), toBytes());
  }

  @override
  int get hashCode => Object.hash(signerIndex, toBytes().hashCode);
}
