/// File-system DKG message relay for CLI `--transport dir`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import 'ceremony_relay.dart';

/// Persists DKG wire bytes under [rootDir]/messages/ for sneakernet workflows.
final class DirectoryCeremonyRelay implements CeremonyMessageRelay {
  DirectoryCeremonyRelay({
    required this.rootDir,
    required this.ceremonyIdHex,
  });

  final Directory rootDir;
  final String ceremonyIdHex;

  Directory get _messageDir =>
      Directory('${rootDir.path}/messages/$ceremonyIdHex');

  @override
  Future<void> publish({
    required String ceremonyId,
    required int senderIndex,
    required Uint8List wireBytes,
    int? recipientIndex,
  }) async {
    if (ceremonyId != ceremonyIdHex) {
      throw ArgumentError('Ceremony id mismatch');
    }
    await _messageDir.create(recursive: true);
    final digest = PqBytes.sha256(wireBytes).join('');
    final recipient = recipientIndex?.toString() ?? 'broadcast';
    final path =
        '${_messageDir.path}/${senderIndex}_${recipient}_$digest.pqthwire';
    await File(path).writeAsBytes(wireBytes, flush: true);
  }

  @override
  Future<List<Uint8List>> fetchInbox({
    required String ceremonyId,
    required int recipientIndex,
  }) async {
    if (ceremonyId != ceremonyIdHex) {
      throw ArgumentError('Ceremony id mismatch');
    }
    if (!await _messageDir.exists()) {
      return const [];
    }
    final out = <Uint8List>[];
    await for (final entity in _messageDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final parts = name.split('_');
      if (parts.length < 3) continue;
      final recipient = parts[1];
      if (recipient != 'broadcast' && recipient != '$recipientIndex') {
        continue;
      }
      out.add(await entity.readAsBytes());
    }
    return out;
  }
}

/// JSON metadata written alongside dir-transport ceremonies.
Future<void> writeCeremonyManifest({
  required Directory rootDir,
  required String ceremonyIdHex,
  required Map<String, Object?> manifest,
}) async {
  final file = File('${rootDir.path}/ceremony.json');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest),
    flush: true,
  );
}
