/// `ceremony run` — C1/C3/C5 orchestrated CLI workflows.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

import '../console.dart';
import '../support.dart';

/// Multi-step ceremony workflows.
final class CeremonyCommand extends Command<void> {
  CeremonyCommand() {
    addSubcommand(CeremonyRunCommand());
  }

  @override
  String get name => 'ceremony';

  @override
  String get description => 'Run C1/C3/C5 ceremony workflows.';
}

final class CeremonyRunCommand extends Command<void> {
  CeremonyRunCommand() {
    addThresholdFlagOptions(argParser, mandatory: false);
    argParser
      ..addOption(
        'flow',
        mandatory: true,
        allowed: ['c1', 'c3', 'c5', 'full'],
        help: 'Ceremony flow to execute (in-process).',
      )
      ..addOption(
        'out-dir',
        valueHelp: 'dir',
        help: 'Write artifacts when set.',
      )
      ..addOption(
        'message',
        valueHelp: 'file',
        help: 'Message file for c3/full.',
      );
  }

  @override
  String get name => 'run';

  @override
  String get description => 'Execute c1, c3, c5, or full C1→C3→C5 (simulate).';

  @override
  Future<void> run() async {
    try {
      final flow = argResults!['flow'] as String;
      final params = _params();
      final outDir = argResults!['out-dir'] as String?;

      switch (flow) {
        case 'c1':
          await _runC1(params, outDir);
        case 'c3':
          await _runC3(params, outDir);
        case 'c5':
          await _runC5(params, outDir);
        case 'full':
          await _runFull(params, outDir);
      }
    } on Object catch (error) {
      handleCliError(error);
    }
  }

  ThresholdParams _params() {
    final t = argResults!['t'] as String?;
    final n = argResults!['n'] as String?;
    if (t != null && n != null) {
      return paramsFromFlags(argResults!);
    }
    return ThresholdParams.tOfN(t: 2, n: 3);
  }

  Future<void> _runC1(ThresholdParams params, String? outDir) async {
    final root = DkgSimulator.run(params: params);
    console.success('C1 DKG ${params.t}-of-${params.n} complete');
    console.detail('publicKey', bytesToHex(root.publicKey.bytes));
    if (outDir != null) {
      await _writeDkgOut(outDir, params, root);
    }
  }

  Future<void> _runC3(ThresholdParams params, String? outDir) async {
    final root = DkgSimulator.run(params: params);
    final message = await _messageBytes();
    final signature = await SigningSimulator.run(
      shares: root.shares,
      message: message,
    );
    final ok = await ThresholdSigner.verify(
      publicKey: root.publicKey,
      message: message,
      signature: signature,
    );
    if (!ok) throw StateError('C3 verify failed');
    console.success('C3 threshold sign verified');
    console.detail('signature-hex', bytesToHex(signature));
    if (outDir != null) {
      await _writeDkgOut(outDir, params, root);
      await File('$outDir/signature.bin').writeAsBytes(signature, flush: true);
      await File('$outDir/message.bin').writeAsBytes(message, flush: true);
    }
  }

  Future<void> _runC5(ThresholdParams params, String? outDir) async {
    final root = DkgSimulator.run(params: params);
    final rotation = await RotationSimulator.run(
      oldShares: root.shares,
      oldPublicKey: root.publicKey,
    );
    final ok = await rotation.continuityProof.verify(
      oldPublicKey: root.publicKey,
    );
    if (!ok) throw StateError('C5 continuity verify failed');
    console.success('C5 rotation complete');
    console.detail('newPublicKey', bytesToHex(rotation.newPublicKey.bytes));
    if (outDir != null) {
      await _writeDkgOut(outDir, params, root);
      await File(
        '$outDir/new-joint.public.pqth',
      ).writeAsBytes(rotation.newPublicKey.toBytes(), flush: true);
      await File(
        '$outDir/continuity.pqth',
      ).writeAsBytes(rotation.continuityProof.toBytes(), flush: true);
    }
  }

  Future<void> _runFull(ThresholdParams params, String? outDir) async {
    await _runC1(params, null);
    await _runC3(params, null);
    await _runC5(params, outDir);
    console.success('Full C1→C3→C5 ceremony OK');
  }

  Future<Uint8List> _messageBytes() async {
    final path = argResults!['message'] as String?;
    if (path != null) return readBytes(path);
    return Uint8List.fromList('pqthreshold-ceremony-message'.codeUnits);
  }

  Future<void> _writeDkgOut(
    String outDir,
    ThresholdParams params,
    ({List<Share> shares, PublicKey publicKey, List<Transcript> transcripts})
    root,
  ) async {
    final dir = Directory(outDir);
    await dir.create(recursive: true);
    await File(
      '$outDir/params.pqth',
    ).writeAsBytes(params.toBytes(), flush: true);
    await File(
      '$outDir/joint.public.pqth',
    ).writeAsBytes(root.publicKey.toBytes(), flush: true);
    await File(
      '$outDir/transcript.pqth',
    ).writeAsBytes(root.transcripts.first.toBytes(), flush: true);
    for (final share in root.shares) {
      await File(
        '$outDir/share-${share.index}.pqth',
      ).writeAsBytes(share.toBytes(), flush: true);
    }
  }
}
