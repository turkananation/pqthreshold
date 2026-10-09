/// Dir-transport helpers for `dkg participant` CLI (v2).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

/// Loads DKG wire messages from a transport directory inbox.
List<DkgMessage> loadDkgInbox({
  required Directory dir,
  required int participantIndex,
}) {
  if (!dir.existsSync()) return const [];
  final messages = <DkgMessage>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final bytes = entity.readAsBytesSync();
    if (bytes.isEmpty) continue;
    final message = DkgMessage.fromBytes(bytes);
    if (message.subKind == DkgWireSubKind.round2) {
      if (message.recipientIndex != participantIndex) continue;
    }
    messages.add(message);
  }
  return messages;
}

/// Writes outbound DKG messages into [dir] using stable filenames.
Future<void> writeDkgOutbox({
  required Directory dir,
  required List<DkgMessage> messages,
}) async {
  await dir.create(recursive: true);
  for (final message in messages) {
    final name = switch (message.subKind) {
      DkgWireSubKind.round2 =>
        'from-${message.senderIndex}-to-${message.recipientIndex}.wire',
      _ => 'from-${message.senderIndex}.wire',
    };
    await File(
      '${dir.path}/$name',
    ).writeAsBytes(message.wireBytes, flush: true);
  }
}

/// Loads FROST Round1/2 wire messages from [dir].
List<FrostSigningMessage> loadFrostMessages(Directory dir) {
  if (!dir.existsSync()) return const [];
  final messages = <FrostSigningMessage>[];
  for (final entity in dir.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final bytes = entity.readAsBytesSync();
    if (bytes.isEmpty) continue;
    messages.add(FrostSigningMessage.fromBytes(bytes));
  }
  return messages;
}

/// Writes a FROST wire message to [dir].
Future<void> writeFrostMessage({
  required Directory dir,
  required FrostSigningMessage message,
}) async {
  await dir.create(recursive: true);
  final name = switch (message.subKind) {
    FrostWireSubKind.round2 => 'round2-from-${message.senderIndex}.wire',
    _ => 'round1-from-${message.senderIndex}.wire',
  };
  await File('${dir.path}/$name').writeAsBytes(message.wireBytes, flush: true);
}

/// Reads all bytes from files in [dir] (non-recursive).
List<Uint8List> readAllFiles(Directory dir) {
  if (!dir.existsSync()) return const [];
  return [
    for (final entity in dir.listSync(followLinks: false))
      if (entity is File) entity.readAsBytesSync(),
  ];
}
