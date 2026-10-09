import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

Uint8List _det(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 17 + length) & 0xFF));

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Future<void> main() async {
  PqRandom.generator = _det;

  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final oldCeremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
  final newCeremonyId = Uint8List.fromList(List.generate(16, (i) => i + 100));
  const signedAt = 1_700_000_000;

  final oldDkg = DkgSimulator.run(params: params, ceremonyId: oldCeremonyId);
  final rotation = await RotationCeremony.simulate(
    oldShares: oldDkg.shares,
    oldPublicKey: oldDkg.publicKey,
    newCeremonyId: newCeremonyId,
    signedAtUnixSeconds: signedAt,
  );

  final body = {
    'format': 'pqthreshold-test-vector-v1',
    'scheme': 'frostEd25519V1',
    'description': '2-of-3 rotation with continuity proof',
    'params': {'t': 2, 'n': 3},
    'ceremonyId': _hex(oldCeremonyId),
    'inputs': {
      'oldCeremonyId': _hex(oldCeremonyId),
      'newCeremonyId': _hex(newCeremonyId),
      'signedAt': signedAt,
    },
    'expected': {
      'oldJointPublicKey': _hex(oldDkg.publicKey.bytes),
      'newJointPublicKey': _hex(rotation.newPublicKey.bytes),
      'continuitySignature': _hex(rotation.continuityProof.thresholdSignature),
    },
  };

  final outDir = Directory('test/vectors/ceremony');
  outDir.createSync(recursive: true);
  File(
    '${outDir.path}/rotation_2of3.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(body)}\n');
}
