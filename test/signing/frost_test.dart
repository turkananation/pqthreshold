import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;
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

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  setUp(() {
    PqRandom.generator = _deterministicRandom;
  });

  tearDown(() {
    PqRandom.generator = PqBytes.randomBytes;
  });

  group('ThresholdSigner', () {
    late ThresholdParams params;
    late Uint8List ceremonyId;
    late PublicKey publicKey;
    late List<Share> shares;
    late Uint8List message;

    setUp(() {
      params = ThresholdParams.tOfN(t: 2, n: 3);
      ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
      message = Uint8List.fromList([0x74, 0x65, 0x73, 0x74]); // "test"
      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      publicKey = dkg.publicKey;
      shares = dkg.shares;
    });

    test('2-of-3 sign and verify succeeds', () async {
      final partials = <PartialSignature>[];
      for (final share in shares.take(2)) {
        partials.add(
          await ThresholdSigner.signPartial(share: share, message: message),
        );
      }

      final signature = ThresholdSigner.combine(
        partials: partials,
        publicKey: publicKey,
        message: message,
      );

      expect(signature.length, 64);
      expect(
        await ThresholdSigner.verify(
          publicKey: publicKey,
          message: message,
          signature: signature,
        ),
        isTrue,
      );
    });

    test('combine with t-1 partials throws InvalidPartialSignature', () async {
      final partial = await ThresholdSigner.signPartial(
        share: shares.first,
        message: message,
      );

      expect(
        () => ThresholdSigner.combine(
          partials: [partial],
          publicKey: publicKey,
          message: message,
        ),
        throwsA(isA<InvalidPartialSignature>()),
      );
    });

    test('verify rejects wrong message', () async {
      final partials = <PartialSignature>[];
      for (final share in shares.take(2)) {
        partials.add(
          await ThresholdSigner.signPartial(share: share, message: message),
        );
      }
      final signature = ThresholdSigner.combine(
        partials: partials,
        publicKey: publicKey,
        message: message,
      );

      expect(
        await ThresholdSigner.verify(
          publicKey: publicKey,
          message: Uint8List.fromList([0x00]),
          signature: signature,
        ),
        isFalse,
      );
    });

    test('PartialSignature serialization round-trip', () async {
      final partial = await ThresholdSigner.signPartial(
        share: shares.first,
        message: message,
      );
      final decoded = PartialSignature.fromBytes(partial.toBytes());
      expect(decoded.signerIndex, partial.signerIndex);
      expect(decoded.messageBinding, partial.messageBinding);
    });

    test('vector signing_2of3.json acceptance criteria', () async {
      final vector = jsonDecode(
        File('test/vectors/frost/signing_2of3.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final params = ThresholdParams.tOfN(
        t: vector['params']['t'] as int,
        n: vector['params']['n'] as int,
      );
      final ceremonyId = _hexToBytes(vector['ceremonyId'] as String);
      final message = _hexToBytes(vector['inputs']['message'] as String);

      final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
      final partials = <PartialSignature>[];
      for (final share in dkg.shares.take(params.t)) {
        partials.add(
          await ThresholdSigner.signPartial(share: share, message: message),
        );
      }

      final signature = ThresholdSigner.combine(
        partials: partials,
        publicKey: dkg.publicKey,
        message: message,
      );

      expect(_hex(signature), vector['expected']['signature']);
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
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
