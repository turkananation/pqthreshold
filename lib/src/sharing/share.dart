/// Threshold [Share] and [PublicKey] types (`doc/API.md` §3.2–3.3).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../errors/threshold_exception.dart';
import '../params/params_validation.dart';
import '../params/threshold_params.dart';
import '../serialization/public_key_codec.dart';
import '../serialization/share_codec.dart';
import '../util/ceremony_id.dart';
import '../util/secret_buffer.dart';

/// A participant's private share plus verification material.
final class Share {
  Share._({
    required this.params,
    required this.ceremonyId,
    required this.participantId,
    required this.index,
    required this._secretShare,
    required this.verificationData,
  });

  /// Threshold parameters bound to this share.
  final ThresholdParams params;

  /// Ceremony identifier (16 bytes).
  final Uint8List ceremonyId;

  /// Application-assigned participant label.
  final String participantId;

  /// 1-based Shamir evaluation index.
  final int index;

  /// Feldman commitments or DKG verification blob.
  final Uint8List verificationData;

  final SecretBuffer _secretShare;

  /// Canonical serialized bytes (`doc/SERIALIZATION.md` §4.2).
  Uint8List toBytes() => ShareCodec.encode(this);

  /// Parses and validates a share.
  factory Share.fromBytes(Uint8List bytes) => ShareCodec.decode(bytes);

  /// Internal construction for VSS/DKG modules.
  @internal
  factory Share.create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int index,
    required Uint8List secretShare,
    required Uint8List verificationData,
  }) {
    validateCeremonyId(ceremonyId);
    validateParticipantId(participantId);
    validateShareIndex(index, params);
    return Share._(
      params: params,
      ceremonyId: Uint8List.fromList(ceremonyId),
      participantId: participantId,
      index: index,
      secretShare: SecretBuffer(Uint8List.fromList(secretShare)),
      verificationData: Uint8List.fromList(verificationData),
    );
  }

  /// Secret scalar bytes — internal use only.
  @internal
  Uint8List secretShareBytes() => Uint8List.fromList(_secretShare.bytes);

  /// Zeroes the secret scalar held by this share.
  ///
  /// Public because a third-party custodian that unwraps a share — for example
  /// to hand it to a signing ceremony — must be able to dispose of it. A
  /// `Share` holding an unwrapped scalar is a live secret, and leaving no
  /// public way to wipe it would make the library's own custody guidance
  /// impossible to follow.
  ///
  /// Safe to call more than once; subsequent calls are no-ops.
  ///
  /// Afterwards any operation that needs the scalar — [toBytes],
  /// [Share.fromBytes]-derived use, or reconstruction — throws a
  /// [StateError] from the underlying [SecretBuffer]. [params], [ceremonyId],
  /// [participantId], [index] and [verificationData] remain readable, as does
  /// [ShareMetadata.fromBytes] on bytes this share produced before disposal.
  void disposeSecret() => _secretShare.dispose();

  @override
  bool operator ==(Object other) {
    return other is Share &&
        other.params == params &&
        PqBytes.constantTimeEquals(other.ceremonyId, ceremonyId) &&
        other.participantId == participantId &&
        other.index == index &&
        PqBytes.constantTimeEquals(other.toBytes(), toBytes());
  }

  @override
  int get hashCode =>
      Object.hash(params, participantId, index, toBytes().hashCode);
}

/// Joint threshold public key material.
final class PublicKey {
  PublicKey._({
    required this.params,
    required this.ceremonyId,
    required this.bytes,
  });

  /// Threshold parameters.
  final ThresholdParams params;

  /// Ceremony identifier (16 bytes).
  final Uint8List ceremonyId;

  /// 32-byte Ed25519 public key in v1.
  final Uint8List bytes;

  /// SHA-256 of canonical encoding — binds partial signatures.
  Uint8List get fingerprint => PqBytes.sha256(toBytes());

  /// Canonical serialized bytes (`doc/SERIALIZATION.md` §4.3).
  Uint8List toBytes() => PublicKeyCodec.encode(this);

  /// Parses a public key.
  factory PublicKey.fromBytes(Uint8List bytes) => PublicKeyCodec.decode(bytes);

  /// Derives the joint public key from a consistent [shares] set (C3/C5).
  factory PublicKey.fromShareSet(List<Share> shares) {
    assertShareSetConsistent(shares);
    return PublicKey.create(
      params: shares.first.params,
      ceremonyId: shares.first.ceremonyId,
      publicKeyBytes: shares.first.verificationData,
    );
  }

  /// Internal construction.
  @internal
  factory PublicKey.create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required Uint8List publicKeyBytes,
  }) {
    validateCeremonyId(ceremonyId);
    if (publicKeyBytes.length != 32) {
      throw InvalidParams('Ed25519 public key must be 32 bytes');
    }
    return PublicKey._(
      params: params,
      ceremonyId: Uint8List.fromList(ceremonyId),
      bytes: Uint8List.fromList(publicKeyBytes),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PublicKey &&
        other.params == params &&
        PqBytes.constantTimeEquals(other.ceremonyId, ceremonyId) &&
        PqBytes.constantTimeEquals(other.bytes, bytes);
  }

  @override
  int get hashCode => Object.hash(params, bytes.hashCode, ceremonyId.hashCode);
}

/// Ensures [shares] belong to one ceremony and params set.
void assertShareSetConsistent(List<Share> shares) {
  if (shares.isEmpty) {
    throw InsufficientShares('No shares provided');
  }
  final params = shares.first.params;
  final ceremonyId = shares.first.ceremonyId;
  for (final share in shares) {
    if (share.params != params) {
      throw InconsistentShares('Shares have mismatched ThresholdParams');
    }
    if (!PqBytes.constantTimeEquals(share.ceremonyId, ceremonyId)) {
      throw WrongCeremony('Shares have mismatched ceremonyId');
    }
  }
}
