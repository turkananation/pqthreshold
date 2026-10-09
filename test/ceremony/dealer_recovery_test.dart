import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
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

  group('DealerCeremony', () {
    test('split and verifyShareFromBlob', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final ceremonyId = generateCeremonyId();
      final secret = Uint8List.fromList(List.generate(32, (i) => i + 3));
      final outcome = DealerCeremony.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );
      expect(outcome.shares.length, 3);
      final blob = outcome.shares.first.verificationData;
      for (final share in outcome.shares) {
        DealerCeremony.verifyShareFromBlob(share: share, commitmentsBlob: blob);
      }
    });
  });

  group('RecoveryCeremony', () {
    test('reconstructSecret matches split secret', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final secret = Uint8List.fromList(List.generate(32, (i) => 0xA0 + i));
      final outcome = DealerCeremony.split(
        params: params,
        ceremonyId: generateCeremonyId(),
        secret: secret,
      );
      final recovered = RecoveryCeremony.reconstructSecret(
        shares: outcome.shares.take(2).toList(),
      );
      expect(recovered, scalarToLeBytes(scalarFromLeBytes(secret)));
    });
  });
}
