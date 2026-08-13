/// `sign run` and round material commands — C3 CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

import '../console.dart';
import '../dkg_transport.dart';
import '../support.dart';

/// Parent command for threshold signing.
final class SignCommand extends Command<void> {
  SignCommand() {
    addSubcommand(SignRunCommand());
    addSubcommand(SignPartialCommand());
    addSubcommand(SignRound2Command());
    addSubcommand(SignCombineCommand());
    addSubcommand(SignVerifyCommand());
  }

  @override
  String get name => 'sign';

  @override
  String get description => 'Threshold signing (C3).';
}

/// One-shot in-process sign from ≥ t share files (operator / CI).
final class SignRunCommand extends Command<void> {
  SignRunCommand() {
    argParser
      ..addMultiOption('share', valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Threshold-sign with ≥ t shares in one process (exports signature).';

  @override
  Future<void> run() async {
    try {
      final paths = argResults!['share'] as List<String>;
      if (paths.isEmpty) {
        throw ArgumentError('At least one --share file is required');
      }
      final shares = [
        for (final path in paths) Share.fromBytes(await readBytes(path)),
      ];
      final message = await readBytes(argResults!['message'] as String);
      final signature = await SigningSimulator.run(
        shares: shares,
        message: message,
      );
      final publicKey = PublicKey.fromShareSet(shares);
      final ok = await ThresholdSigner.verify(
        publicKey: publicKey,
        message: message,
        signature: signature,
      );
      if (!ok) throw StateError('Generated signature failed verify');
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(signature, flush: true);
      console.success('Threshold signature written (${signature.length} bytes)');
      console.detail('signature-hex', bytesToHex(signature));
      console.created(out);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// Round-one FROST commitments from one share (v2 dir transport).
final class SignPartialCommand extends Command<void> {
  SignPartialCommand() {
    argParser
      ..addOption('share', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file', help: 'Round1 wire message.')
      ..addOption(
        'session-out',
        mandatory: true,
        valueHelp: 'file',
        help: 'Officer-local checkpoint (secrets — do not publish).',
      );
  }

  @override
  String get name => 'partial';

  @override
  String get description =>
      'FROST Round1: export wire commitments and local session checkpoint.';

  @override
  Future<void> run() async {
    try {
      final share = Share.fromBytes(await readBytes(argResults!['share'] as String));
      final message = await readBytes(argResults!['message'] as String);
      final begun = await SigningSession.begin(share: share, message: message);
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(begun.round1.wireBytes, flush: true);
      final sessionOut = argResults!['session-out'] as String;
      await File(sessionOut).writeAsBytes(begun.session.toCheckpoint(), flush: true);
      console.success('Round1 wire + session checkpoint written');
      console.detail('signerIndex', '${share.index}');
      console.created(out);
      console.created(sessionOut);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// Round-two partial scalar after collecting Round1 wire messages.
final class SignRound2Command extends Command<void> {
  SignRound2Command() {
    argParser
      ..addOption('session', mandatory: true, valueHelp: 'file')
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('round1-dir', mandatory: true, valueHelp: 'dir')
      ..addOption('out', mandatory: true, valueHelp: 'file', help: 'Round2 wire message.')
      ..addOption('partial-out', valueHelp: 'file', help: 'Optional PQTH partial for combine.');
  }

  @override
  String get name => 'round2';

  @override
  String get description =>
      'FROST Round2: complete partial scalar from Round1 dir + session checkpoint.';

  @override
  Future<void> run() async {
    SigningSession? session;
    try {
      session = SigningSession.fromCheckpoint(
        await readBytes(argResults!['session'] as String),
      );
      final publicKey = PublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final round1Dir = Directory(argResults!['round1-dir'] as String);
      final round1 = loadFrostMessages(round1Dir)
          .where((m) => m.subKind == FrostWireSubKind.round1)
          .toList();
      final partial = session.completeRound2(
        round1Messages: round1,
        publicKey: publicKey,
      );
      final wire = frostRound2WireFromPartial(partial: partial, params: publicKey.params);
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(wire.wireBytes, flush: true);
      final partialOut = argResults!['partial-out'] as String?;
      if (partialOut != null) {
        await File(partialOut).writeAsBytes(partial.toBytes(), flush: true);
      }
      console.success('Round2 wire written');
      console.created(out);
      session.dispose();
    } on Object catch (error) {
      session?.dispose();
      handleCliError(error);
    }
  }
}

/// Combines Round2 wire messages (or in-memory partials) into Ed25519 signature.
final class SignCombineCommand extends Command<void> {
  SignCombineCommand() {
    argParser
      ..addMultiOption('partial', valueHelp: 'file')
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file')
      ..addOption(
        'round1-dir',
        valueHelp: 'dir',
        help: 'With --round2-dir: combine distributed FROST wire messages.',
      )
      ..addOption('round2-dir', valueHelp: 'dir');
  }

  @override
  String get name => 'combine';

  @override
  String get description =>
      'Combine partials or Round1+Round2 wire dirs into Ed25519 signature.';

  @override
  Future<void> run() async {
    try {
      final publicKey = PublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);

      final List<PartialSignature> partials;
      final round1Dir = argResults!['round1-dir'] as String?;
      final round2Dir = argResults!['round2-dir'] as String?;
      if (round1Dir != null && round2Dir != null) {
        final round1 = loadFrostMessages(Directory(round1Dir));
        final round2 = loadFrostMessages(Directory(round2Dir))
            .where((m) => m.subKind == FrostWireSubKind.round2)
            .toList();
        partials = partialsFromRound2Messages(
          round1Messages: round1,
          round2Messages: round2,
          publicKey: publicKey,
        );
      } else {
        final paths = argResults!['partial'] as List<String>;
        if (paths.isEmpty) {
          throw ArgumentError(
            'Provide --partial files or both --round1-dir and --round2-dir',
          );
        }
        partials = [
          for (final path in paths)
            PartialSignature.fromBytes(await readBytes(path)),
        ];
      }

      final signature = ThresholdSigner.combine(
        partials: partials,
        publicKey: publicKey,
        message: message,
      );
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(signature, flush: true);
      console.success('Combined ${signature.length}-byte Ed25519 signature');
      console.detail('signature-hex', bytesToHex(signature));
      console.created(out);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// Verifies threshold-produced Ed25519 signature (exit 0/1).
final class SignVerifyCommand extends Command<void> {
  SignVerifyCommand() {
    argParser
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('signature', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'verify';

  @override
  String get description =>
      'Verify joint public key + message + signature (pqforge-compatible Ed25519).';

  @override
  Future<void> run() async {
    try {
      final publicKey = PublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);
      final signature = await readBytes(argResults!['signature'] as String);
      final ok = await ThresholdSigner.verify(
        publicKey: publicKey,
        message: message,
        signature: signature,
      );
      if (ok) {
        console.success('Signature valid');
        exitCode = 0;
      } else {
        console.failure('Signature invalid');
        exitCode = 1;
      }
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}
