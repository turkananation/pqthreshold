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

  group('DkgSimulator', () {
    late Uint8List ceremonyId;

    setUp(() {
      ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
    });

    test('2-of-3 simulation derives consistent joint public key', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final outcome = DkgSimulator.run(
        params: params,
        ceremonyId: ceremonyId,
      );

      expect(outcome.shares.length, 3);
      expect(outcome.publicKey.bytes.length, 32);
      expect(outcome.transcripts.length, 3);

      final shareBytes = outcome.shares.map((s) => s.toBytes()).toSet();
      expect(shareBytes.length, 3, reason: 'each party gets a distinct share');

      for (final transcript in outcome.transcripts) {
        expect(transcript.verify(), isTrue);
        expect(transcript.toBytes(), isNotEmpty);
        expect(
          Transcript.fromBytes(transcript.toBytes()).verify(),
          isTrue,
        );
      }
    });

    test('3-of-5 simulation succeeds', () {
      final params = ThresholdParams.tOfN(t: 3, n: 5);
      final outcome = DkgSimulator.run(
        params: params,
        ceremonyId: ceremonyId,
      );

      expect(outcome.shares.length, 5);
      final indices = outcome.shares.map((s) => s.index).toSet();
      expect(indices, {1, 2, 3, 4, 5});
    });

    test('CeremonySession round progression', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final session = CeremonySession.create(
        params: params,
        ceremonyId: ceremonyId,
        participantId: 'alice',
        participantIndex: 1,
      );

      expect(session.round, 1);
      final round1 = session.processInbox(const []);
      expect(round1, hasLength(1));
      expect(round1.single.subKind, DkgWireSubKind.round1);
    });

    test('vector 2of3_simulated.json acceptance criteria', () {
      final vector = jsonDecode(
        File('test/vectors/dkg/2of3_simulated.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final params = ThresholdParams.tOfN(
        t: vector['params']['t'] as int,
        n: vector['params']['n'] as int,
      );
      final ceremonyId = _hexToBytes(vector['ceremonyId'] as String);
      final outcome = DkgSimulator.run(
        params: params,
        ceremonyId: ceremonyId,
      );

      expect(
        _hex(outcome.publicKey.bytes),
        vector['expected']['jointPublicKey'],
      );
    });

    test('vector 3of5_simulated.json acceptance criteria', () {
      final vector = jsonDecode(
        File('test/vectors/dkg/3of5_simulated.json').readAsStringSync(),
      ) as Map<String, dynamic>;

      final params = ThresholdParams.tOfN(
        t: vector['params']['t'] as int,
        n: vector['params']['n'] as int,
      );
      final ceremonyId = _hexToBytes(vector['ceremonyId'] as String);
      final outcome = DkgSimulator.run(
        params: params,
        ceremonyId: ceremonyId,
      );

      expect(
        _hex(outcome.publicKey.bytes),
        vector['expected']['jointPublicKey'],
      );
      final shareHexes = outcome.shares.map((s) => _hex(s.secretShareBytes())).toList()
        ..sort();
      final expectedShares = (vector['expected']['shares'] as List<dynamic>)
          .cast<String>()
        ..sort();
      expect(shareHexes, expectedShares);
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
