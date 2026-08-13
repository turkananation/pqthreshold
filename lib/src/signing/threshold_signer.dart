/// Public FROST threshold signing API (`doc/API.md` §4.3).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;

import '../errors/threshold_exception.dart';
import '../scheme/feldman/ed25519_curve_ops.dart';
import '../scheme/feldman/ed25519_scalar.dart';
import '../scheme/frost/frost_identifier.dart';
import '../scheme/frost/frost_signing.dart';
import '../sharing/share.dart';
import 'partial_signature.dart';

/// FROST threshold signing over Ed25519 (C3).
abstract final class ThresholdSigner {
  /// Round-one: generates commitments; stores ephemeral material until [combine].
  ///
  /// Partials contain sensitive nonce and share material and must not be
  /// persisted or transmitted before [combine]. Production deployments should
  /// use the wire round messages in `doc/PROTOCOL_MESSAGES.md` §5 instead.
  static Future<PartialSignature> signPartial({
    required Share share,
    required Uint8List message,
    Uint8List? context,
  }) async {
    final publicKey = _jointPublicKeyFromShare(share);
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
    return PartialSignature.create(
      ceremonyId: share.ceremonyId,
      publicKeyFingerprint: publicKey.fingerprint,
      signerIndex: share.index,
      messageBinding: binding,
      hidingCommitment: commitment.hiding,
      bindingCommitment: commitment.binding,
      hidingNonce: scalarToLeBytes(nonces.hiding),
      bindingNonce: scalarToLeBytes(nonces.binding),
      secretShare: share.secretShareBytes(),
    );
  }

  /// Aggregates **≥ t** partials into a 64-byte Ed25519 signature.
  static Uint8List combine({
    required List<PartialSignature> partials,
    required PublicKey publicKey,
    required Uint8List message,
    Uint8List? context,
  }) {
    if (partials.isEmpty) {
      throw InvalidPartialSignature('No partial signatures provided');
    }
    if (partials.length < publicKey.params.t) {
      throw InvalidPartialSignature(
        'Need at least ${publicKey.params.t} partials, got ${partials.length}',
      );
    }

    final binding = messageBindingFor(
      publicKey: publicKey,
      message: message,
      context: context,
    );
    final frostId = buildFrostIdentifier(
      ceremonyId: publicKey.ceremonyId,
      params: publicKey.params,
    );

    final selected = partials.take(publicKey.params.t).toList();
    _validatePartialSet(selected, publicKey, binding);

    final indices = selected.map((p) => p.signerIndex).toList();
    if (indices.toSet().length != indices.length) {
      throw InvalidPartialSignature('Duplicate signer indices in partial set');
    }

    final commitments = [
      for (final p in selected)
        FrostCommitment(
          index: p.signerIndex,
          hiding: p.hidingCommitment,
          binding: p.bindingCommitment,
        ),
    ];

    final bindingFactors = FrostSigning.computeBindingFactors(
      frostIdentifier: frostId,
      groupPublicKey: publicKey.bytes,
      message: message,
      commitments: commitments,
    );
    final groupCommitment = FrostSigning.computeGroupCommitment(
      commitments: commitments,
      bindingFactors: bindingFactors,
    );
    final challenge = FrostSigning.computeChallenge(
      frostIdentifier: frostId,
      groupCommitment: groupCommitment,
      groupPublicKey: publicKey.bytes,
      message: message,
    );

    final signatureShares = <BigInt>[];

    for (final partial in selected) {
      late BigInt z;
      Uint8List? sharePk;

      if (partial.hasEphemeralNonces) {
        final sk = partial.secretShareScalar();
        final hiding = partial.hidingNonceScalar();
        final bindingNonce = partial.bindingNonceScalar();
        if (sk == null || hiding == null || bindingNonce == null) {
          throw InvalidPartialSignature('Incomplete signing material in partial');
        }
        sharePk = Ed25519CurveOps.scalarBaseMult(scalarToLeBytes(sk));
        final nonces = FrostNonces(hiding: hiding, binding: bindingNonce);
        z = FrostSigning.computeSignatureShare(
          signerIndex: partial.signerIndex,
          secretShare: sk,
          nonces: nonces,
          bindingFactor: bindingFactors[partial.signerIndex]!,
          challenge: challenge,
          signerIndices: indices,
        );
      } else {
        z = scalarFromLeBytes(partial.partialScalar);
        if (partial.partialScalar.every((b) => b == 0)) {
          throw InvalidPartialSignature(
            'Partial from signer ${partial.signerIndex} missing scalar',
          );
        }
      }

      if (sharePk != null) {
        final valid = FrostSigning.verifySignatureShare(
          signerIndex: partial.signerIndex,
          sharePublicKey: sharePk,
          commitment: FrostCommitment(
            index: partial.signerIndex,
            hiding: partial.hidingCommitment,
            binding: partial.bindingCommitment,
          ),
          signatureShare: z,
          bindingFactors: bindingFactors,
          challenge: challenge,
          signerIndices: indices,
        );
        if (!valid) {
          throw InvalidPartialSignature(
            'Invalid signature share from signer ${partial.signerIndex}',
          );
        }
      }

      signatureShares.add(z);
      partial.disposeEphemeralNonces();
    }

    return FrostSigning.aggregateSignature(
      groupCommitment: groupCommitment,
      signatureShares: signatureShares,
    );
  }

  /// Verifies [signature] via pqforge Ed25519 (`doc/FROST_PROFILE.md` §7).
  static Future<bool> verify({
    required PublicKey publicKey,
    required Uint8List message,
    required Uint8List signature,
    Uint8List? context,
  }) {
    if (signature.length != 64) {
      return Future.value(false);
    }
    return PqClassical.provider.ed25519Verify(
      publicKey: publicKey.bytes,
      message: message,
      signature: signature,
    );
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

  static void _validatePartialSet(
    List<PartialSignature> partials,
    PublicKey publicKey,
    Uint8List expectedBinding,
  ) {
    for (final partial in partials) {
      if (!PqBytes.constantTimeEquals(partial.ceremonyId, publicKey.ceremonyId)) {
        throw WrongCeremony('PartialSignature ceremonyId mismatch');
      }
      if (!PqBytes.constantTimeEquals(
        partial.publicKeyFingerprint,
        publicKey.fingerprint,
      )) {
        throw InvalidPartialSignature(
          'PartialSignature public key fingerprint mismatch',
        );
      }
      if (!PqBytes.constantTimeEquals(partial.messageBinding, expectedBinding)) {
        throw InvalidPartialSignature('PartialSignature message binding mismatch');
      }
      if (partial.signerIndex < 1 || partial.signerIndex > publicKey.params.n) {
        throw InvalidPartialSignature('PartialSignature signer index out of range');
      }
    }
  }
}
