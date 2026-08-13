/// `vss split|verify|reconstruct` — C2 dealer ceremony CLI.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';

import '../console.dart';
import '../support.dart';

/// Parent command for Feldman VSS (C2).
final class VssCommand extends Command<void> {
  VssCommand() {
    addSubcommand(VssSplitCommand());
    addSubcommand(VssVerifyCommand());
    addSubcommand(VssReconstructCommand());
  }

  @override
  String get name => 'vss';

  @override
  String get description => 'Dealer-based verifiable secret sharing (C2).';
}

final class VssSplitCommand extends Command<void> {
  VssSplitCommand() {
    addThresholdFlagOptions(argParser, mandatory: true);
    argParser
      ..addOption(
        'secret-hex',
        valueHelp: 'hex',
        help: '32-byte secret scalar as 64 hex chars.',
      )
      ..addOption(
        'ceremony-id-hex',
        valueHelp: 'hex',
        help: '16-byte ceremony id (32 hex chars); random if omitted.',
      )
      ..addOption(
        'out-dir',
        mandatory: true,
        valueHelp: 'dir',
        help: 'Output directory for shares and public key.',
      );
  }

  @override
  String get name => 'split';

  @override
  String get description => 'Dealer splits a secret into n verifiable shares.';

  @override
  Future<void> run() async {
    try {
      final params = paramsFromFlags(argResults!);
      final secretHex = argResults!['secret-hex'] as String?;
      final cidHex = argResults!['ceremony-id-hex'] as String?;
      final outDir = Directory(argResults!['out-dir'] as String);

      final secret = secretHex == null
          ? Uint8List.fromList(List.generate(32, (i) => i + 1))
          : hexToBytes(secretHex);
      if (secret.length != 32) {
        throw ArgumentError('secret must be 32 bytes (64 hex chars)');
      }

      final ceremonyId = cidHex == null ? generateCeremonyId() : hexToBytes(cidHex);
      if (ceremonyId.length != 16) {
        throw ArgumentError('ceremony-id-hex must be 32 hex chars');
      }

      final outcome = DealerCeremony.split(
        params: params,
        ceremonyId: ceremonyId,
        secret: secret,
      );

      await outDir.create(recursive: true);
      await File('${outDir.path}/params.pqth')
          .writeAsBytes(params.toBytes(), flush: true);
      await File('${outDir.path}/joint.public.pqth')
          .writeAsBytes(outcome.publicKey.toBytes(), flush: true);
      await File('${outDir.path}/ceremony.id')
          .writeAsBytes(ceremonyId, flush: true);

      for (final share in outcome.shares) {
        final path =
            '${outDir.path}/share-${share.index}.${share.participantId}.pqth';
        await File(path).writeAsBytes(share.toBytes(), flush: true);
      }
      await File('${outDir.path}/commitments.blob').writeAsBytes(
        outcome.shares.first.verificationData,
        flush: true,
      );

      console.success('Split ${params.t}-of-${params.n} into ${outcome.shares.length} shares');
      console.detail('ceremonyId', bytesToHex(ceremonyId));
      console.detail('out-dir', outDir.path);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

final class VssVerifyCommand extends Command<void> {
  VssVerifyCommand() {
    argParser
      ..addOption('share', mandatory: true, valueHelp: 'file')
      ..addOption(
        'commitments',
        valueHelp: 'file',
        help: 'Feldman commitments blob from split (defaults to share embedded data).',
      );
  }

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify one share against published verification data.';

  @override
  Future<void> run() async {
    try {
      final share = Share.fromBytes(await readBytes(argResults!['share'] as String));
      final commitmentsPath = argResults!['commitments'] as String?;
      final blob = commitmentsPath == null
          ? share.verificationData
          : await readBytes(commitmentsPath);
      DealerCeremony.verifyShareFromBlob(share: share, commitmentsBlob: blob);
      console.success('Share ${share.index} (${share.participantId}) verifies');
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

final class VssReconstructCommand extends Command<void> {
  VssReconstructCommand() {
    argParser
      ..addMultiOption('share', valueHelp: 'file')
      ..addFlag('yes', help: 'Confirm high-privilege secret reconstruction.');
  }

  @override
  String get name => 'reconstruct';

  @override
  String get description => 'Reconstruct dealer secret from t shares (C4).';

  @override
  Future<void> run() async {
    try {
      if (!(argResults!['yes'] as bool)) {
        throw ArgumentError('Reconstruction is high-privilege — pass --yes');
      }
      final paths = argResults!['share'] as List<String>;
      if (paths.isEmpty) {
        throw ArgumentError('At least one --share file is required');
      }
      final shares = [
        for (final path in paths) Share.fromBytes(await readBytes(path)),
      ];
      final secret = RecoveryCeremony.reconstructSecret(shares: shares);
      console.success('Reconstructed ${secret.length}-byte secret');
      console.detail('secret-hex', bytesToHex(secret));
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}
