import 'dart:io';
import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

/// End-to-end C1 → C3 → C5 flow using Tier 2 simulators.
///
/// See `doc/CEREMONIES.md`, `doc/GETTING_STARTED.md` §7, and `doc/INTEGRATION.md`.
Future<void> main() async {
  // Uses platform CSPRNG via pqforge defaults — do NOT set
  // PqRandom.generator = PqBytes.randomBytes (that recurses infinitely).

  stdout.writeln('pqthreshold example — C1 → C3 → C5');
  stdout.writeln();

  // C1 — dealer-less root DKG
  stdout.writeln('[C1] Running 2-of-3 DKG…');
  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final root = DkgSimulator.run(params: params);
  stdout.writeln('     Joint public key: ${_hex(root.publicKey.bytes)}');
  stdout.writeln('     Shares issued: ${root.shares.length}');

  // C3 — threshold sign a credential
  stdout.writeln('[C3] Threshold-signing credential…');
  final credential = Uint8List.fromList('membership-v1'.codeUnits);
  final signature = await SigningSimulator.run(
    shares: root.shares,
    message: credential,
  );
  final verified = await ThresholdSigner.verify(
    publicKey: root.publicKey,
    message: credential,
    signature: signature,
  );
  stdout.writeln('     Signature: ${_hex(signature)}');
  stdout.writeln('     Verify: $verified');
  if (!verified) {
    throw StateError('C3 verify failed');
  }

  // C5 — rotate to a new threshold key with continuity proof
  stdout.writeln('[C5] Rotating root with continuity proof…');
  final rotation = await RotationSimulator.run(
    oldShares: root.shares,
    oldPublicKey: root.publicKey,
  );
  final continuityOk = await rotation.continuityProof.verify(
    oldPublicKey: root.publicKey,
  );
  stdout.writeln('     New public key: ${_hex(rotation.newPublicKey.bytes)}');
  stdout.writeln('     Continuity verify: $continuityOk');
  if (!continuityOk) {
    throw StateError('C5 continuity verify failed');
  }

  // New key can sign under the rotated root
  stdout.writeln('[C3] Signing under rotated key…');
  final nextCredential = Uint8List.fromList('membership-v2'.codeUnits);
  final nextSig = await SigningSimulator.run(
    shares: rotation.newShares,
    message: nextCredential,
  );
  final nextVerified = await ThresholdSigner.verify(
    publicKey: rotation.newPublicKey,
    message: nextCredential,
    signature: nextSig,
  );
  stdout.writeln('     Verify: $nextVerified');
  if (!nextVerified) {
    throw StateError('Post-rotation sign verify failed');
  }

  stdout.writeln();
  stdout.writeln('Example OK — all ceremonies succeeded.');
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Test hook: same flow without printing (for unit tests).
Future<void> runExampleFlow({void Function(String line)? log}) async {
  void say(String line) => log?.call(line);

  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final root = DkgSimulator.run(params: params);
  say('shares=${root.shares.length}');

  final credential = Uint8List.fromList('membership-v1'.codeUnits);
  final signature = await SigningSimulator.run(
    shares: root.shares,
    message: credential,
  );
  if (!await ThresholdSigner.verify(
    publicKey: root.publicKey,
    message: credential,
    signature: signature,
  )) {
    throw StateError('C3 verify failed');
  }

  final rotation = await RotationSimulator.run(
    oldShares: root.shares,
    oldPublicKey: root.publicKey,
  );
  if (!await rotation.continuityProof.verify(oldPublicKey: root.publicKey)) {
    throw StateError('C5 continuity verify failed');
  }

  final nextCredential = Uint8List.fromList('membership-v2'.codeUnits);
  final nextSig = await SigningSimulator.run(
    shares: rotation.newShares,
    message: nextCredential,
  );
  if (!await ThresholdSigner.verify(
    publicKey: rotation.newPublicKey,
    message: nextCredential,
    signature: nextSig,
  )) {
    throw StateError('Post-rotation verify failed');
  }
}
