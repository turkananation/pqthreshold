/// PQTH share wrapping aligned with pqforge custody ([TERMINAL.md] §5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';

/// pqforge [PqExportedKey.kind] for wrapped threshold shares.
const thresholdShareKeyKind = 'threshold-share';

/// pqforge [PqExportedKey.algorithmId] for PQTH Share bytes.
const thresholdShareAlgorithmId = 'pqthreshold/pqth-share-v1';

/// Wraps [share] with pqforge Argon2id + AES-GCM (same model as device keys).
PqWrappedKey wrapShareWithPassphrase({
  required Share share,
  required String passphrase,
  String? keyId,
}) {
  final forge = PqForge();
  final exported = PqExportedKey(
    kind: thresholdShareKeyKind,
    algorithmId: thresholdShareAlgorithmId,
    bytes: share.toBytes(),
    keyId: keyId ?? share.participantId,
  );
  return forge.wrapKeyWithPassphrase(exported, passphrase);
}

/// Restores [Share] from a pqforge wrapped envelope.
Share unwrapShareWithPassphrase({
  required PqWrappedKey wrapped,
  required String passphrase,
}) {
  if (wrapped.keyKind != thresholdShareKeyKind) {
    throw FormatException('Expected keyKind $thresholdShareKeyKind');
  }
  final forge = PqForge();
  final exported = forge.unwrapKeyWithPassphrase(wrapped, passphrase);
  return Share.fromBytes(exported.bytes);
}

/// Writes `*.share.wrapped.json` (TERMINAL.md §6).
Future<void> writeWrappedShareFile({
  required String path,
  required PqWrappedKey wrapped,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(wrapped.toJson()),
    flush: true,
  );
}

/// Reads wrapped share JSON from disk.
Future<PqWrappedKey> readWrappedShareFile(String path) async {
  final json =
      jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
  return PqWrappedKey.fromJson(json);
}
