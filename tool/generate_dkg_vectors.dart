import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

Uint8List _det(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 17 + length) & 0xFF));

String _hex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  PqRandom.generator = _det;
  final ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));

  void writeVector({
    required String path,
    required String description,
    required int t,
    required int n,
    bool includeShares = false,
  }) {
    final params = ThresholdParams.tOfN(t: t, n: n);
    final outcome = DkgSimulator.run(
      params: params,
      ceremonyId: ceremonyId,
    );
    final expected = <String, dynamic>{
      'jointPublicKey': _hex(outcome.publicKey.bytes),
    };
    if (includeShares) {
      expected['shares'] = outcome.shares
          .map((s) => _hex(s.secretShareBytes()))
          .toList();
    }
    final body = {
      'format': 'pqthreshold-test-vector-v1',
      'scheme': 'frostEd25519V1',
      'description': description,
      'params': {'t': t, 'n': n},
      'ceremonyId': _hex(ceremonyId),
      'expected': expected,
    };
    File(path).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(body)}\n',
    );
  }

  writeVector(
    path: 'test/vectors/dkg/2of3_simulated.json',
    description: '2-of-3 simulated DKG joint public key',
    t: 2,
    n: 3,
  );

  writeVector(
    path: 'test/vectors/dkg/3of5_simulated.json',
    description: '3-of-5 simulated DKG shares and joint public key',
    t: 3,
    n: 5,
    includeShares: true,
  );
}
