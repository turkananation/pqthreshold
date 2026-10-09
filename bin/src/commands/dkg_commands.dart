/// `dkg simulate` and `dkg participant` — C1 CLI.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

import '../console.dart';
import '../dkg_transport.dart';
import '../support.dart';

/// Parent command for distributed key generation (C1).
final class DkgCommand extends Command<void> {
  DkgCommand() {
    addSubcommand(DkgSimulateCommand());
    addSubcommand(DkgParticipantCommand());
  }

  @override
  String get name => 'dkg';

  @override
  String get description => 'Distributed key generation ceremonies (C1).';
}

/// Runs full in-process DKG and writes PQTH artifacts (Tier 2 harness).
final class DkgSimulateCommand extends Command<void> {
  DkgSimulateCommand() {
    addThresholdFlagOptions(argParser, mandatory: true);
    argParser
      ..addOption(
        'out-dir',
        mandatory: true,
        valueHelp: 'dir',
        help: 'Write params, shares, public key, transcripts.',
      )
      ..addOption(
        'ceremony-id-hex',
        valueHelp: 'hex',
        help: 'Optional 16-byte ceremony id (32 hex chars).',
      );
  }

  @override
  String get name => 'simulate';

  @override
  String get description =>
      'Simulate full C1 DKG in-process and export artifacts (operator/CI).';

  @override
  Future<void> run() async {
    try {
      final params = paramsFromFlags(argResults!);
      final cidHex = argResults!['ceremony-id-hex'] as String?;
      final ceremonyId = cidHex == null ? null : hexToBytes(cidHex);
      if (ceremonyId != null && ceremonyId.length != 16) {
        throw ArgumentError('ceremony-id-hex must be 32 hex chars');
      }

      final outcome = DkgSimulator.run(params: params, ceremonyId: ceremonyId);

      final outDir = Directory(argResults!['out-dir'] as String);
      await outDir.create(recursive: true);
      final cid = outcome.publicKey.ceremonyId;

      await File(
        '${outDir.path}/params.pqth',
      ).writeAsBytes(params.toBytes(), flush: true);
      await File('${outDir.path}/ceremony.id').writeAsBytes(cid, flush: true);
      await File(
        '${outDir.path}/joint.public.pqth',
      ).writeAsBytes(outcome.publicKey.toBytes(), flush: true);
      await File(
        '${outDir.path}/transcript.pqth',
      ).writeAsBytes(outcome.transcripts.first.toBytes(), flush: true);

      for (final share in outcome.shares) {
        final path =
            '${outDir.path}/share-${share.index}.${share.participantId}.pqth';
        await File(path).writeAsBytes(share.toBytes(), flush: true);
      }

      console.success('DKG ${params.t}-of-${params.n} complete');
      console.detail('ceremonyId', bytesToHex(cid));
      console.detail('publicKey', bytesToHex(outcome.publicKey.bytes));
      console.detail('out-dir', outDir.path);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// One dir-transport DKG step for a single participant (v2).
final class DkgParticipantCommand extends Command<void> {
  DkgParticipantCommand() {
    addSubcommand(DkgParticipantStepCommand());
  }

  @override
  String get name => 'participant';

  @override
  String get description => 'Multi-party C1 over shared transport directories.';
}

final class DkgParticipantStepCommand extends Command<void> {
  DkgParticipantStepCommand() {
    addThresholdFlagOptions(argParser, mandatory: true);
    argParser
      ..addOption(
        'ceremony-dir',
        mandatory: true,
        valueHelp: 'dir',
        help: 'Ceremony workspace (params, transport/, officers/).',
      )
      ..addOption(
        'participant-id',
        mandatory: true,
        valueHelp: 'id',
        help: 'Officer identifier (e.g. alice).',
      )
      ..addOption(
        'index',
        mandatory: true,
        valueHelp: 'int',
        help: '1-based participant index.',
      )
      ..addOption(
        'ceremony-id-hex',
        valueHelp: 'hex',
        help: '16-byte ceremony id (32 hex); random if omitted on first run.',
      );
  }

  @override
  String get name => 'step';

  @override
  String get description =>
      'Run one DKG round: read transport inbox, write outbox, save checkpoint.';

  @override
  Future<void> run() async {
    try {
      final params = paramsFromFlags(argResults!);
      final ceremonyDir = Directory(argResults!['ceremony-dir'] as String);
      await ceremonyDir.create(recursive: true);
      final participantId = argResults!['participant-id'] as String;
      final indexRaw = argResults!['index'] as String;
      final participantIndex = int.tryParse(indexRaw);
      if (participantIndex == null || participantIndex < 1) {
        throw ArgumentError('--index must be a positive integer');
      }

      final paramsFile = File('${ceremonyDir.path}/params.pqth');
      await paramsFile.writeAsBytes(params.toBytes(), flush: true);

      final cidHex = argResults!['ceremony-id-hex'] as String?;
      final ceremonyIdFile = File('${ceremonyDir.path}/ceremony.id');
      late Uint8List ceremonyId;
      if (await ceremonyIdFile.exists()) {
        ceremonyId = await ceremonyIdFile.readAsBytes();
      } else if (cidHex != null) {
        ceremonyId = hexToBytes(cidHex);
        await ceremonyIdFile.writeAsBytes(ceremonyId, flush: true);
      } else {
        ceremonyId = generateCeremonyId();
        await ceremonyIdFile.writeAsBytes(ceremonyId, flush: true);
      }
      if (ceremonyId.length != 16) {
        throw ArgumentError('ceremony id must be 16 bytes');
      }

      final officerDir = Directory(
        '${ceremonyDir.path}/officers/$participantId',
      );
      await officerDir.create(recursive: true);
      final checkpointFile = File('${officerDir.path}/dkg.checkpoint');

      final CeremonySession session;
      if (await checkpointFile.exists()) {
        session = CeremonySession.fromCheckpoint(
          await checkpointFile.readAsBytes(),
        );
      } else {
        session = CeremonySession.create(
          params: params,
          ceremonyId: ceremonyId,
          participantId: participantId,
          participantIndex: participantIndex,
        );
      }

      final transport = Directory('${ceremonyDir.path}/transport');
      final round1Dir = Directory('${transport.path}/round1');
      final round2Dir = Directory('${transport.path}/round2');
      final inbox = [
        ...loadDkgInbox(dir: round1Dir, participantIndex: participantIndex),
        ...loadDkgInbox(dir: round2Dir, participantIndex: participantIndex),
      ];

      final outbox = session.processInbox(inbox);
      if (outbox.isNotEmpty) {
        final round1Out = <DkgMessage>[];
        final round2Out = <DkgMessage>[];
        for (final message in outbox) {
          if (message.subKind == DkgWireSubKind.round2) {
            round2Out.add(message);
          } else {
            round1Out.add(message);
          }
        }
        if (round1Out.isNotEmpty) {
          await writeDkgOutbox(dir: round1Dir, messages: round1Out);
        }
        if (round2Out.isNotEmpty) {
          await writeDkgOutbox(dir: round2Dir, messages: round2Out);
        }
      }

      await checkpointFile.writeAsBytes(
        session.exportCheckpoint(),
        flush: true,
      );

      console.detail('round', '${session.round}');
      console.detail('outbox', '${outbox.length} message(s)');

      if (session.isComplete) {
        final result = session.finalize();
        await File(
          '${officerDir.path}/share.pqth',
        ).writeAsBytes(result.share.toBytes(), flush: true);
        await File(
          '${ceremonyDir.path}/joint.public.pqth',
        ).writeAsBytes(result.publicKey.toBytes(), flush: true);
        await File(
          '${ceremonyDir.path}/transcript.pqth',
        ).writeAsBytes(result.transcript.toBytes(), flush: true);
        console.success('DKG finalize complete for $participantId');
        console.detail('publicKey', bytesToHex(result.publicKey.bytes));
      } else {
        console.success('DKG step complete (round ${session.round})');
      }
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}
