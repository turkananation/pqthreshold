import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

Uint8List _det(int length) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 17 + length) & 0xFF));

String _hex(Uint8List b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Future<void> main() async {
  PqRandom.generator = _det;
  final ceremonyId = Uint8List.fromList(List.generate(16, (i) => i + 1));
  final message = Uint8List.fromList([0x74, 0x65, 0x73, 0x74]);
  final params = ThresholdParams.tOfN(t: 2, n: 3);

  final dkg = DkgSimulator.run(params: params, ceremonyId: ceremonyId);
  final partials = <PartialSignature>[];
  for (final share in dkg.shares.take(2)) {
    partials.add(await ThresholdSigner.signPartial(share: share, message: message));
  }
  final signature = ThresholdSigner.combine(
    partials: partials,
    publicKey: dkg.publicKey,
    message: message,
  );

  final body = {
    'format': 'pqthreshold-test-vector-v1',
    'scheme': 'frostEd25519V1',
    'description': '2-of-3 FROST signing over DKG key',
    'params': {'t': 2, 'n': 3},
    'ceremonyId': _hex(ceremonyId),
    'inputs': {'message': _hex(message)},
    'expected': {
      'signature': _hex(signature),
      'jointPublicKey': _hex(dkg.publicKey.bytes),
    },
  };

  File('test/vectors/frost/signing_2of3.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(body)}\n',
  );
}
