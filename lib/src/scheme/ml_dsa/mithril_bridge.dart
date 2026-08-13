/// Mithril threshold ML-DSA bridge (Rust subprocess, M2 beta).
///
/// Pure Dart lattice MPC is planned; until then the bridge invokes
/// [threshold-ml-dsa](https://github.com/lattice-safe/threshold-ml-dsa) for
/// ML-DSA-44 threshold keygen and signing.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pqforge/pqforge.dart';

import '../../errors/threshold_exception.dart';
import '../../params/scheme_id.dart';
import 'ml_dsa_profile.dart';

/// Locates the `mithril_bridge` release binary.
@internal
String mithrilBridgeExecutable({String? overridePath}) {
  if (overridePath != null && overridePath.isNotEmpty) {
    return overridePath;
  }
  final env = Platform.environment['PQTH_MITHRIL_BRIDGE'];
  if (env != null && env.isNotEmpty) {
    return env;
  }
  // Relative to package root when running from checkout.
  final candidates = [
    'tool/mithril_bridge/target/release/mithril_bridge',
    '../pqthreshold/tool/mithril_bridge/target/release/mithril_bridge',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  throw SchemeNotImplemented(
    'mithril_bridge binary not found. Build with: '
    'cd tool/mithril_bridge && cargo build --release',
  );
}

/// Whether the Mithril bridge binary is available on this machine.
bool mithrilBridgeAvailable({String? overridePath}) {
  try {
    mithrilBridgeExecutable(overridePath: overridePath);
    return true;
  } on SchemeNotImplemented {
    return false;
  }
}

/// Runs a JSON request against [mithril_bridge].
@internal
Future<Map<String, dynamic>> mithrilBridgeRequest(
  Map<String, dynamic> request, {
  String? executablePath,
}) async {
  MlDsaThresholdProfile.fromScheme(SchemeId.mlDsa44ThresholdV1);

  final exe = mithrilBridgeExecutable(overridePath: executablePath);
  final process = await Process.start(
    exe,
    [],
    workingDirectory: Directory.current.path,
    runInShell: false,
    environment: Platform.environment,
  );
  process.stdin.add(utf8.encode(jsonEncode(request)));
  await process.stdin.close();
  final stdoutBytes = (await process.stdout.toList())
      .expand((chunk) => chunk)
      .toList();
  final stderrText = utf8.decode(
    (await process.stderr.toList()).expand((chunk) => chunk).toList(),
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw CeremonyAborted(
      'mithril_bridge failed (exit $exitCode): $stderrText',
    );
  }
  final decoded = jsonDecode(utf8.decode(stdoutBytes)) as Map<String, dynamic>;
  if (decoded.containsKey('error')) {
    throw CeremonyAborted('mithril_bridge: ${decoded['error']}');
  }
  return decoded;
}

/// Threshold keygen via Mithril (ML-DSA-44); returns FIPS 204 public key bytes.
@internal
Future<({
  Uint8List publicKey,
  Uint8List ceremonySeed,
  int t,
  int n,
})> mithrilKeygen({
  required int t,
  required int n,
  Uint8List? seed,
  String? executablePath,
}) async {
  final ceremonySeed = seed ?? PqBytes.randomBytes(32);
  if (ceremonySeed.length != 32) {
    throw InvalidParams('Mithril keygen seed must be 32 bytes');
  }
  final response = await mithrilBridgeRequest(
    {
      'op': 'keygen',
      't': t,
      'n': n,
      'seed_hex': _bytesToHex(ceremonySeed),
    },
    executablePath: executablePath,
  );
  final pk = base64Decode(response['public_key_b64'] as String);
  return (
    publicKey: Uint8List.fromList(pk),
    ceremonySeed: Uint8List.fromList(ceremonySeed),
    t: response['t'] as int,
    n: response['n'] as int,
  );
}

/// Threshold sign via Mithril; output verifies with [MlDsaThresholdVerifier].
@internal
Future<Uint8List> mithrilThresholdSign({
  required int t,
  required int n,
  required Uint8List ceremonySeed,
  required List<int> activePartyIdsZeroBased,
  required Uint8List message,
  Uint8List? rngSeed,
  String? executablePath,
}) async {
  if (ceremonySeed.length != 32) {
    throw InvalidParams('ceremonySeed must be 32 bytes');
  }
  activePartyIdsZeroBased.sort();
  final response = await mithrilBridgeRequest(
    {
      'op': 'threshold_sign',
      't': t,
      'n': n,
      'seed_hex': _bytesToHex(ceremonySeed),
      'active': activePartyIdsZeroBased,
      'message_b64': base64Encode(message),
      if (rngSeed != null) 'rng_seed_hex': _bytesToHex(rngSeed),
    },
    executablePath: executablePath,
  );
  return Uint8List.fromList(
    base64Decode(response['signature_b64'] as String),
  );
}

/// Runs Mithril rounds 1–3 and returns wire payloads plus combined signature.
@internal
Future<({
  Uint8List sessionId,
  Uint8List signature,
  Map<String, dynamic> wireJson,
})> mithrilWireSign({
  required int t,
  required int n,
  required Uint8List ceremonySeed,
  required List<int> activePartyIdsZeroBased,
  required Uint8List message,
  Uint8List? rngSeed,
  String? executablePath,
}) async {
  if (ceremonySeed.length != 32) {
    throw InvalidParams('ceremonySeed must be 32 bytes');
  }
  activePartyIdsZeroBased.sort();
  final response = await mithrilBridgeRequest(
    {
      'op': 'wire_sign',
      't': t,
      'n': n,
      'seed_hex': _bytesToHex(ceremonySeed),
      'active': activePartyIdsZeroBased,
      'message_b64': base64Encode(message),
      if (rngSeed != null) 'rng_seed_hex': _bytesToHex(rngSeed),
    },
    executablePath: executablePath,
  );
  return (
    sessionId: Uint8List.fromList(
      base64Decode(response['session_id_b64'] as String),
    ),
    signature: Uint8List.fromList(
      base64Decode(response['signature_b64'] as String),
    ),
    wireJson: response,
  );
}

String _bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
