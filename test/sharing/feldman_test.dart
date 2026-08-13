import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/src/scheme/feldman/ed25519_scalar.dart';
import 'package:test/test.dart';

Uint8List _deterministicRandom(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i * 17 + length) & 0xFF;
  }
  return out;
}

void main() {
  setUp(() {
    PqRandom.generator = _deterministicRandom;
  });

  tearDown(() {
    PqRandom.generator = PqBytes.randomBytes;
  });

  group('Feldman VSS', () {
    late ThresholdParams params;
    late Uint8List ceremonyId;
    late Uint8List secret;

    setUp(() {
      params = ThresholdParams.tOfN(t: 2, n: 3);
      ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
      secret = Uint8List.fromList(List.generate(32, (i) => 0xA0 + i));
    });

    test('split and reconstruct with t shares succeeds', () {
      final outcome = VerifiableSecretSharing.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );

      expect(outcome.shares.length, 3);
      expect(outcome.verificationData.length, 2);
      expect(outcome.publicKey.bytes.length, 32);

      for (final share in outcome.shares) {
        VerifiableSecretSharing.verifyShare(
          share: share,
          verificationData: outcome.verificationData,
        );
      }

      final reconstructed = VerifiableSecretSharing.reconstruct(
        shares: outcome.shares.take(2).toList(),
      );
      expect(
        reconstructed,
        scalarToLeBytes(scalarFromLeBytes(secret)),
      );
    });

    test('reconstruct with t-1 shares throws InsufficientShares', () {
      final outcome = VerifiableSecretSharing.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );

      expect(
        () => VerifiableSecretSharing.reconstruct(
          shares: [outcome.shares.first],
        ),
        throwsA(isA<InsufficientShares>()),
      );
    });

    test('verifyShare rejects tampered share scalar', () {
      final outcome = VerifiableSecretSharing.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );
      final share = outcome.shares.first;
      final tamperedBytes = share.toBytes();
      tamperedBytes[tamperedBytes.length - 5] ^= 0xFF;
      final tampered = Share.fromBytes(tamperedBytes);

      expect(
        () => VerifiableSecretSharing.verifyShare(
          share: tampered,
          verificationData: outcome.verificationData,
        ),
        throwsA(isA<InconsistentShares>()),
      );
    });

    test('Share and PublicKey serialization round-trip', () {
      final outcome = VerifiableSecretSharing.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );
      final share = Share.fromBytes(outcome.shares.first.toBytes());
      final publicKey = PublicKey.fromBytes(outcome.publicKey.toBytes());

      expect(share.index, 1);
      expect(publicKey.bytes, outcome.publicKey.bytes);
      expect(share.toBytes(), outcome.shares.first.toBytes());
    });

    test('vector 2of3_valid.json acceptance criteria', () {
      final vectorFile = File('test/vectors/feldman/2of3_valid.json');
      expect(vectorFile.existsSync(), isTrue, reason: 'missing test vector');

      final json = jsonDecode(vectorFile.readAsStringSync()) as Map<String, dynamic>;
      expect(json['format'], 'pqthreshold-test-vector-v1');

      final t = (json['params'] as Map)['t'] as int;
      final n = (json['params'] as Map)['n'] as int;
      final vectorParams = ThresholdParams.tOfN(t: t, n: n);
      final vectorCeremony = _hexToBytes(json['ceremonyId'] as String);
      final inputSecret = _hexToBytes(json['inputs']['secret'] as String);
      final expectedSecret = _hexToBytes(json['expected']['secret'] as String);
      final expectedPublic = _hexToBytes(json['expected']['jointPublicKey'] as String);

      final outcome = VerifiableSecretSharing.split(
        params: vectorParams,
        ceremonyId: vectorCeremony,
        secret: inputSecret,
      );

      expect(outcome.publicKey.bytes, expectedPublic);
      final reconstructed = VerifiableSecretSharing.reconstruct(
        shares: outcome.shares.take(t).toList(),
      );
      expect(reconstructed, expectedSecret);
    });

    test('vector 2of3_insufficient.json acceptance criteria', () {
      final vectorFile = File('test/vectors/feldman/2of3_insufficient.json');
      expect(vectorFile.existsSync(), isTrue);

      final json = jsonDecode(vectorFile.readAsStringSync()) as Map<String, dynamic>;
      final t = (json['params'] as Map)['t'] as int;
      final n = (json['params'] as Map)['n'] as int;
      final vectorParams = ThresholdParams.tOfN(t: t, n: n);
      final vectorCeremony = _hexToBytes(json['ceremonyId'] as String);
      final inputSecret = _hexToBytes(json['inputs']['secret'] as String);

      final outcome = VerifiableSecretSharing.split(
        params: vectorParams,
        ceremonyId: vectorCeremony,
        secret: inputSecret,
      );

      expect(
        () => VerifiableSecretSharing.reconstruct(
          shares: [outcome.shares.first],
        ),
        throwsA(isA<InsufficientShares>()),
      );
    });
  });
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
