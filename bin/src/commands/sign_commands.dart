/// `sign run` and round material commands — C3 CLI.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/testing.dart';

import '../console.dart';
import '../support.dart';

/// Parent command for threshold signing.
final class SignCommand extends Command<void> {
  SignCommand() {
    addSubcommand(SignRunCommand());
    addSubcommand(SignPartialCommand());
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

/// Partial FROST signature from one share.
final class SignPartialCommand extends Command<void> {
  SignPartialCommand() {
    argParser
      ..addOption('share', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'partial';

  @override
  String get description =>
      'Export round-1 commitments (combine in-process or use sign run).';

  @override
  Future<void> run() async {
    try {
      final share = Share.fromBytes(await readBytes(argResults!['share'] as String));
      final message = await readBytes(argResults!['message'] as String);
      final partial = await ThresholdSigner.signPartial(
        share: share,
        message: message,
      );
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(partial.toBytes(), flush: true);
      console.success('Round-1 partial material from index ${share.index}');
      console.created(out);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// Combines in-memory partials (same process as partial generation).
final class SignCombineCommand extends Command<void> {
  SignCombineCommand() {
    argParser
      ..addMultiOption('partial', valueHelp: 'file')
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'combine';

  @override
  String get description =>
      'Combine partials that still hold ephemeral material (prefer sign run).';

  @override
  Future<void> run() async {
    try {
      final paths = argResults!['partial'] as List<String>;
      if (paths.isEmpty) {
        throw ArgumentError('At least one --partial file is required');
      }
      final partials = [
        for (final path in paths)
          PartialSignature.fromBytes(await readBytes(path)),
      ];
      final publicKey = PublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);
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
