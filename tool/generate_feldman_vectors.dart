import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/src/scheme/feldman/ed25519_scalar.dart';

Uint8List _det(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 17 + length) & 0xFF));

String _hex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  PqRandom.generator = _det;
  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
  final secretRaw = Uint8List.fromList(List.generate(32, (i) => 0xA0 + i));
  final secret = scalarToLeBytes(scalarFromLeBytes(secretRaw));

  final outcome = VerifiableSecretSharing.split(
    params: params,
    ceremonyId: ceremonyId,
    secret: secret,
  );

  final valid = {
    'format': 'pqthreshold-test-vector-v1',
    'scheme': 'frostEd25519V1',
    'description': '2-of-3 Feldman split and reconstruct',
    'params': {'t': 2, 'n': 3},
    'ceremonyId': _hex(ceremonyId),
    'inputs': {'secret': _hex(secret)},
    'expected': {
      'secret': _hex(secret),
      'jointPublicKey': _hex(outcome.publicKey.bytes),
    },
  };
  File('test/vectors/feldman/2of3_valid.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(valid)}\n',
  );

  final insufficient = {
    'format': 'pqthreshold-test-vector-v1',
    'scheme': 'frostEd25519V1',
    'description': '2-of-3 reconstruct with one share must fail',
    'params': {'t': 2, 'n': 3},
    'ceremonyId': _hex(ceremonyId),
    'inputs': {'secret': _hex(secret)},
    'expected': {'error': 'InsufficientShares'},
  };
  File('test/vectors/feldman/2of3_insufficient.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(insufficient)}\n',
  );
}
