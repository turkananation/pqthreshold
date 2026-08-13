import 'dart:typed_data';

import 'package:pqforge/pqforge.dart' hide PublicKey;
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

/// End-to-end C1 → C3 → C5 flow using Tier 2 simulators.
///
/// See `doc/CEREMONIES.md` and `doc/INTEGRATION.md` §11.
Future<void> main() async {
  PqRandom.generator = PqBytes.randomBytes;

  // C1 — dealer-less root DKG
  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final root = DkgSimulator.run(params: params);
  assert(root.shares.length == params.n);
  assert(root.publicKey.bytes.length == 32);

  // C3 — threshold sign a credential
  final credential = Uint8List.fromList('membership-v1'.codeUnits);
  final signature = await SigningSimulator.run(
    shares: root.shares,
    message: credential,
  );
  assert(
    await ThresholdSigner.verify(
      publicKey: root.publicKey,
      message: credential,
      signature: signature,
    ),
  );

  // C5 — rotate to a new threshold key with continuity proof
  final rotation = await RotationSimulator.run(
    oldShares: root.shares,
    oldPublicKey: root.publicKey,
  );
  assert(
    await rotation.continuityProof.verify(oldPublicKey: root.publicKey),
  );

  // New key can sign under the rotated root
  final nextCredential = Uint8List.fromList('membership-v2'.codeUnits);
  final nextSig = await SigningSimulator.run(
    shares: rotation.newShares,
    message: nextCredential,
  );
  assert(
    await ThresholdSigner.verify(
      publicKey: rotation.newPublicKey,
      message: nextCredential,
      signature: nextSig,
    ),
  );
}
