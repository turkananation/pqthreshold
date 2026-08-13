/// ML-DSA threshold share and public key types (`doc/ML_DSA_THRESHOLD_PROFILE.md` §6).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/threshold_params.dart';
import '../../util/ceremony_id.dart';
import '../../util/secret_buffer.dart';
import 'ml_dsa_profile.dart';
import 'ml_dsa_public_key_codec.dart';
import 'ml_dsa_share_codec.dart';

/// Participant share for ML-DSA threshold schemes (v2).
///
/// M2 beta (Tier 2 simulate): holds a ceremony [ceremonySeed] shared across
/// simulated officers — production distributed DKG will replace this with
/// per-party RSS material once exported from lattice DKG.
final class MlDsaShare {
  MlDsaShare._({
    required this.params,
    required this.ceremonyId,
    required this.participantId,
    required this.index,
    required this._ceremonySeed,
  });

  /// Threshold parameters.
  final ThresholdParams params;

  /// Ceremony identifier (16 bytes).
  final Uint8List ceremonyId;

  /// Application-assigned participant label.
  final String participantId;

  /// 1-based participant index (maps to Mithril party id `index - 1`).
  final int index;

  final SecretBuffer _ceremonySeed;

  /// Canonical PQTH bytes (kind `0x09` share extension — see codec).
  Uint8List toBytes() => MlDsaShareCodec.encode(this);

  /// Parses a share from canonical bytes.
  factory MlDsaShare.fromBytes(Uint8List bytes) => MlDsaShareCodec.decode(bytes);

  /// Creates a simulated share (Tier 2 / tests only).
  @internal
  factory MlDsaShare.simulate({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int index,
    required Uint8List ceremonySeed,
  }) =>
      MlDsaShare._create(
        params: params,
        ceremonyId: ceremonyId,
        participantId: participantId,
        index: index,
        ceremonySeed: ceremonySeed,
      );

  factory MlDsaShare._create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int index,
    required Uint8List ceremonySeed,
  }) {
    validateCeremonyId(ceremonyId);
    if (!MlDsaThresholdProfile.matchesScheme(params.scheme)) {
      throw InvalidParams('Scheme ${params.scheme} is not ML-DSA threshold');
    }
    if (participantId.isEmpty || participantId.codeUnits.length > 256) {
      throw InvalidParams('participantId must be 1..256 UTF-8 bytes');
    }
    if (index < 1 || index > params.n) {
      throw InvalidParams('Share index $index out of range 1..${params.n}');
    }
    if (ceremonySeed.length != 32) {
      throw InvalidParams('ceremonySeed must be 32 bytes');
    }
    return MlDsaShare._(
      params: params,
      ceremonyId: Uint8List.fromList(ceremonyId),
      participantId: participantId,
      index: index,
      ceremonySeed: SecretBuffer(Uint8List.fromList(ceremonySeed)),
    );
  }

  /// Mithril party id (0-based).
  int get mithrilPartyId => index - 1;

  /// Ceremony seed for M2 beta simulate path — sensitive.
  @internal
  Uint8List ceremonySeedBytes() => Uint8List.fromList(_ceremonySeed.bytes);

  @internal
  void disposeSecret() => _ceremonySeed.dispose();

  @override
  bool operator ==(Object other) {
    return other is MlDsaShare &&
        PqBytes.constantTimeEquals(other.toBytes(), toBytes());
  }

  @override
  int get hashCode => toBytes().hashCode;
}

/// Joint ML-DSA public key for a threshold ceremony (FIPS 204 encoding).
final class MlDsaPublicKey {
  MlDsaPublicKey._({
    required this.params,
    required this.ceremonyId,
    required this.bytes,
  });

  /// Threshold parameters.
  final ThresholdParams params;

  /// Ceremony identifier.
  final Uint8List ceremonyId;

  /// FIPS 204 public key bytes (variable length per parameter set).
  final Uint8List bytes;

  /// SHA-256 fingerprint for binding partials.
  late final Uint8List fingerprint = PqBytes.sha256(toBytes());

  /// Canonical PQTH bytes (kind `0x07`).
  Uint8List toBytes() => MlDsaPublicKeyCodec.encode(this);

  factory MlDsaPublicKey.fromBytes(Uint8List raw) =>
      MlDsaPublicKeyCodec.decode(raw);

  /// Creates a validated public key.
  factory MlDsaPublicKey.create({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required Uint8List publicKeyBytes,
  }) {
    validateCeremonyId(ceremonyId);
    final profile = MlDsaThresholdProfile.fromScheme(params.scheme);
    if (publicKeyBytes.length != profile.publicKeyLength) {
      throw InvalidParams(
        'ML-DSA public key length ${publicKeyBytes.length} != ${profile.publicKeyLength}',
      );
    }
    return MlDsaPublicKey._(
      params: params,
      ceremonyId: Uint8List.fromList(ceremonyId),
      bytes: Uint8List.fromList(publicKeyBytes),
    );
  }
}

/// Ensures all [shares] belong to one ceremony and scheme.
void assertMlDsaShareSetConsistent(List<MlDsaShare> shares) {
  if (shares.isEmpty) {
    throw InsufficientShares('No ML-DSA shares provided');
  }
  final first = shares.first;
  for (final share in shares.skip(1)) {
    if (share.params != first.params ||
        !PqBytes.constantTimeEquals(share.ceremonyId, first.ceremonyId)) {
      throw WrongCeremony('ML-DSA shares are from different ceremonies');
    }
  }
}
