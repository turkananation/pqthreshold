/// `dkg simulate` and `dkg participant` — C1 CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/testing.dart';

import '../console.dart';
import '../support.dart';

/// Parent command for distributed key generation (C1).
final class DkgCommand extends Command<void> {
  DkgCommand() {
    addSubcommand(DkgSimulateCommand());
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

      final outcome = DkgSimulator.run(
        params: params,
        ceremonyId: ceremonyId,
      );

      final outDir = Directory(argResults!['out-dir'] as String);
      await outDir.create(recursive: true);
      final cid = outcome.publicKey.ceremonyId;

      await File('${outDir.path}/params.pqth')
          .writeAsBytes(params.toBytes(), flush: true);
      await File('${outDir.path}/ceremony.id').writeAsBytes(cid, flush: true);
      await File('${outDir.path}/joint.public.pqth')
          .writeAsBytes(outcome.publicKey.toBytes(), flush: true);
      await File('${outDir.path}/transcript.pqth')
          .writeAsBytes(outcome.transcripts.first.toBytes(), flush: true);

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
