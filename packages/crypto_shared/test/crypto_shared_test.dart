import 'dart:typed_data';

import 'package:crypto_shared/crypto_shared.dart';
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

  group('hex codec', () {
    test('round-trip ceremony id', () {
      final id = generateCeremonyId();
      final hex = ceremonyIdToHex(id);
      expect(hex.length, 32);
      expect(ceremonyIdFromHex(hex), id);
    });
  });

  group('DistributedDkgCoordinator', () {
    test('2-of-3 completes over InMemoryCeremonyRelay', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final relay = InMemoryCeremonyRelay();
      final outcome = await DistributedDkgCoordinator.run(
        params: params,
        relay: relay,
      );

      expect(outcome.shares.length, 3);
      expect(outcome.publicKey.bytes.length, 32);
      expect(outcome.transcripts.length, 3);
      for (final share in outcome.shares) {
        expect(share.params, params);
      }
    });
  });

  group('SigningJobCoordinator', () {
    test('combines after t partials', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final dkg = DkgSimulator.run(params: params);
      final message = Uint8List.fromList('job-test'.codeUnits);
      final coordinator = SigningJobCoordinator();

      final jobId = coordinator.createJob(
        publicKey: dkg.publicKey,
        message: message,
      );

      final partial1 = await ThresholdSigner.signPartial(
        share: dkg.shares[0],
        message: message,
      );
      final partial2 = await ThresholdSigner.signPartial(
        share: dkg.shares[1],
        message: message,
      );

      coordinator.submitPartial(jobId: jobId, partial: partial1);
      expect(coordinator.tryCombine(jobId), isNull);

      coordinator.submitPartial(jobId: jobId, partial: partial2);
      final sig = coordinator.tryCombine(jobId);
      expect(sig, isNotNull);
      expect(
        await ThresholdSigner.verify(
          publicKey: dkg.publicKey,
          message: message,
          signature: sig!,
        ),
        isTrue,
      );
    });
  });

  group('ThresholdCeremonyService', () {
    test('relay DKG via service API', () async {
      final service = ThresholdCeremonyService();
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final ceremonyId = generateCeremonyId();
      final ceremonyIdHex = ceremonyIdToHex(ceremonyId);

      final outcome = await DistributedDkgCoordinator.run(
        params: params,
        relay: service.relay,
        ceremonyId: ceremonyId,
      );

      service.publishPublicKey(
        ceremonyIdHex: ceremonyIdHex,
        publicKeyBytes: outcome.publicKey.toBytes(),
      );
      service.publishTranscript(
        ceremonyIdHex: ceremonyIdHex,
        transcriptBytes: outcome.transcripts.first.toBytes(),
      );

      expect(service.publicKeyBytes(ceremonyIdHex), isNotNull);
      expect(service.transcriptBytes(ceremonyIdHex), isNotNull);

      final message = Uint8List.fromList('service-sign'.codeUnits);
      final jobId = service.signing.createJob(
        publicKey: outcome.publicKey,
        message: message,
      );

      final p1 = await ThresholdSigner.signPartial(
        share: outcome.shares[0],
        message: message,
      );
      final p2 = await ThresholdSigner.signPartial(
        share: outcome.shares[1],
        message: message,
      );
      service.signing.submitPartial(jobId: jobId, partial: p1);
      service.signing.submitPartial(jobId: jobId, partial: p2);
      final sig = service.signing.tryCombine(jobId)!;

      expect(
        await service.verifyThresholdSignature(
          publicKeyBytes: outcome.publicKey.toBytes(),
          message: message,
          signature: sig,
        ),
        isTrue,
      );
    });
  });
}
