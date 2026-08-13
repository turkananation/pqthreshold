import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';
import 'package:test/test.dart';

Uint8List _deterministicRandom(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i * 19 + length) & 0xFF;
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

  group('RootCeremony', () {
    test('simulate matches DkgSimulator outcome', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 10));

      final root = await RootCeremony.simulate(
        params,
        ceremonyId: ceremonyId,
      );
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);

      expect(root.shares.length, dkg.shares.length);
      expect(root.publicKey.bytes, dkg.publicKey.bytes);
    });

    test('startSession creates a usable session', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final ceremonyId = generateCeremonyId();
      final session = RootCeremony.startSession(
        params: params,
        ceremonyId: ceremonyId,
        participantId: 'alice',
        participantIndex: 1,
      );
      expect(session.participantIndex, 1);
      expect(session.isComplete, isFalse);
    });
  });

  group('ThresholdSigningCeremony', () {
    test('simulate produces verifiable signature', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final dkg = DkgSimulator.run(params: params);
      final message = Uint8List.fromList([0x01, 0x02, 0x03]);

      final signature = await ThresholdSigningCeremony.simulate(
        shares: dkg.shares,
        message: message,
      );

      expect(signature.length, 64);
      expect(
        await ThresholdSigner.verify(
          publicKey: dkg.publicKey,
          message: message,
          signature: signature,
        ),
        isTrue,
      );
    });
  });

  group('ContinuityProof', () {
    test('rotation simulate produces verifiable proof', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final oldCeremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final newCeremonyId = Uint8List.fromList(List.generate(16, (i) => i + 100));
      final oldDkg = DkgSimulator.run(
        params: params,
        ceremonyId: oldCeremonyId,
      );
      final signedAt = 1_700_000_000;

      final rotation = await RotationCeremony.simulate(
        oldShares: oldDkg.shares,
        oldPublicKey: oldDkg.publicKey,
        newCeremonyId: newCeremonyId,
        signedAtUnixSeconds: signedAt,
      );

      expect(
        await rotation.continuityProof.verify(oldPublicKey: oldDkg.publicKey),
        isTrue,
      );
      expect(rotation.continuityProof.newCeremonyId, newCeremonyId);
      expect(rotation.newShares.length, params.n);
    });

    test('serialization round-trip', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final oldDkg = DkgSimulator.run(params: params);

      final rotation = await RotationCeremony.simulate(
        oldShares: oldDkg.shares,
        oldPublicKey: oldDkg.publicKey,
      );

      final decoded = ContinuityProof.fromBytes(
        rotation.continuityProof.toBytes(),
      );
      expect(decoded.oldCeremonyId, rotation.continuityProof.oldCeremonyId);
      expect(decoded.newPublicKeyBytes, rotation.continuityProof.newPublicKeyBytes);
      expect(
        await decoded.verify(oldPublicKey: oldDkg.publicKey),
        isTrue,
      );
    });

    test('verify rejects wrong old public key', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final oldDkg = DkgSimulator.run(params: params);

      final rotation = await RotationCeremony.simulate(
        oldShares: oldDkg.shares,
        oldPublicKey: oldDkg.publicKey,
      );

      final wrongKey = PublicKey.create(
        params: params,
        ceremonyId: oldDkg.publicKey.ceremonyId,
        publicKeyBytes: Uint8List.fromList(List.filled(32, 0x42)),
      );

      expect(
        await rotation.continuityProof.verify(oldPublicKey: wrongKey),
        isFalse,
      );
    });
  });
}
