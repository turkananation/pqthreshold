import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';
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

  group('PQTH durable object round-trips', () {
    late ThresholdParams params;
    late Uint8List ceremonyId;
    late Uint8List otherCeremonyId;

    setUp(() {
      params = ThresholdParams.tOfN(t: 2, n: 3);
      ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
      otherCeremonyId = Uint8List.fromList(List.generate(16, (i) => i + 50));
    });

    test('ThresholdParams', () {
      final original = ThresholdParams.tOfN(t: 3, n: 5);
      final bytes = original.toBytes();
      final decoded = ThresholdParams.fromBytes(bytes);
      expect(decoded, original);
      expect(decoded.toBytes(), bytes);
    });

    test('Share', () {
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final original = dkg.shares.first;
      final bytes = original.toBytes();
      final decoded = Share.fromBytes(bytes);
      expect(decoded.toBytes(), bytes);
      expect(decoded.index, original.index);
      expect(decoded.participantId, original.participantId);
    });

    test('PublicKey', () {
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final bytes = dkg.publicKey.toBytes();
      final decoded = PublicKey.fromBytes(bytes);
      expect(decoded.toBytes(), bytes);
      expect(decoded.bytes, dkg.publicKey.bytes);
    });

    test('PartialSignature', () async {
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final message = Uint8List.fromList([0x01, 0x02]);
      final partial = await ThresholdSigner.signPartial(
        share: dkg.shares.first,
        message: message,
      );
      final bytes = partial.toBytes();
      final decoded = PartialSignature.fromBytes(bytes);
      expect(decoded.toBytes(), bytes);
      expect(decoded.signerIndex, partial.signerIndex);
    });

    test('Transcript', () {
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final original = dkg.transcripts.first;
      final bytes = original.toBytes();
      final decoded = Transcript.fromBytes(bytes);
      expect(decoded.toBytes(), bytes);
      expect(decoded.verify(), isTrue);
    });

    test('ContinuityProof', () async {
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final rotation = await RotationCeremony.simulate(
        oldShares: dkg.shares,
        oldPublicKey: dkg.publicKey,
        newCeremonyId: otherCeremonyId,
        signedAtUnixSeconds: 1_700_000_000,
      );
      final bytes = rotation.continuityProof.toBytes();
      final decoded = ContinuityProof.fromBytes(bytes);
      expect(decoded.toBytes(), bytes);
      expect(
        decoded.thresholdSignature,
        rotation.continuityProof.thresholdSignature,
      );
    });
  });

  group('WrongCeremony binding', () {
    test('assertShareSetConsistent rejects mixed ceremonyId', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final cidA = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final cidB = Uint8List.fromList(List.generate(16, (i) => i + 2));
      final dkgA = DkgSimulator.run(params: params, ceremonyId: cidA);
      final dkgB = DkgSimulator.run(params: params, ceremonyId: cidB);

      expect(
        () => assertShareSetConsistent([dkgA.shares.first, dkgB.shares.first]),
        throwsA(isA<WrongCeremony>()),
      );
    });

    test(
      'ThresholdSigner.combine rejects partial from another ceremony',
      () async {
        final params = ThresholdParams.tOfN(t: 2, n: 3);
        final cidA = Uint8List.fromList(List.generate(16, (i) => i + 1));
        final cidB = Uint8List.fromList(List.generate(16, (i) => i + 2));
        final dkgA = DkgSimulator.run(params: params, ceremonyId: cidA);
        final dkgB = DkgSimulator.run(params: params, ceremonyId: cidB);
        final message = Uint8List.fromList([0xAB]);

        final partialA = await ThresholdSigner.signPartial(
          share: dkgA.shares.first,
          message: message,
        );
        final partialB = await ThresholdSigner.signPartial(
          share: dkgB.shares[1],
          message: message,
        );

        expect(
          () => ThresholdSigner.combine(
            partials: [partialA, partialB],
            publicKey: dkgA.publicKey,
            message: message,
          ),
          throwsA(isA<WrongCeremony>()),
        );
      },
    );

    test('DkgMessage rejects wrong ceremonyId on ingest', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final cidA = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final cidB = Uint8List.fromList(List.generate(16, (i) => i + 2));
      final session = CeremonySession.create(
        params: params,
        ceremonyId: cidA,
        participantId: 'alice',
        participantIndex: 1,
      );
      session.processInbox(const []);
      final foreign = session.processInbox(const []);
      if (foreign.isEmpty) {
        return;
      }
      // Build a message bound to a different ceremony.
      final round1 = DkgMessage.round1(
        params: params,
        ceremonyId: cidB,
        senderIndex: 2,
        commitments: List.generate(
          params.t,
          (_) => Uint8List.fromList(List.filled(32, 0x11)),
        ),
      );
      expect(
        () => session.processInbox([round1]),
        throwsA(isA<WrongCeremony>()),
      );
    });
  });
}
