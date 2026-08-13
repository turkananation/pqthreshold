import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';
import 'package:test/test.dart';

Uint8List _deterministicRandom(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = (i * 13 + 7) & 0xFF;
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

  test('two-round FROST wire round-trip matches sign run', () async {
    final root = DkgSimulator.run(params: ThresholdParams.tOfN(t: 2, n: 3));
    final message = Uint8List.fromList([9, 8, 7]);
    final publicKey = root.publicKey;
    final signers = root.shares.take(2).toList();

    final round1Messages = <FrostSigningMessage>[];
    final sessions = <SigningSession>[];
    for (final share in signers) {
      final begun = await SigningSession.begin(share: share, message: message);
      round1Messages.add(begun.round1);
      sessions.add(begun.session);
    }

    final round2Partials = <PartialSignature>[];
    for (final session in sessions) {
      round2Partials.add(
        session.completeRound2(
          round1Messages: round1Messages,
          publicKey: publicKey,
        ),
      );
    }

    final fromWire = partialsFromRound2Messages(
      round1Messages: round1Messages,
      round2Messages: [
        for (final p in round2Partials)
          frostRound2WireFromPartial(partial: p, params: publicKey.params),
      ],
      publicKey: publicKey,
    );

    final signature = ThresholdSigner.combine(
      partials: fromWire,
      publicKey: publicKey,
      message: message,
    );

    final ok = await ThresholdSigner.verify(
      publicKey: publicKey,
      message: message,
      signature: signature,
    );
    expect(ok, isTrue);

    for (final session in sessions) {
      session.dispose();
    }
  });

  test('signing session checkpoint round-trips Round2', () async {
    final root = DkgSimulator.run(params: ThresholdParams.tOfN(t: 2, n: 3));
    final message = Uint8List.fromList([1, 2, 3]);
    final share = root.shares.first;
    final begun = await SigningSession.begin(share: share, message: message);
    final checkpoint = begun.session.toCheckpoint();
    begun.session.dispose();

    final restored = SigningSession.fromCheckpoint(checkpoint);
    final begun2 = await SigningSession.begin(share: root.shares[1], message: message);
    final round1 = [begun.round1, begun2.round1];

    final partial = restored.completeRound2(
      round1Messages: round1,
      publicKey: root.publicKey,
    );
    expect(partial.partialScalar.any((b) => b != 0), isTrue);
    restored.dispose();
    begun2.session.dispose();
  });
}
