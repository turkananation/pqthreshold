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
    addSubcommand(SignMlDsaCommand());
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
    SigningSession? session;
    try {
      final share = Share.fromBytes(await readBytes(argResults!['share'] as String));
      final message = await readBytes(argResults!['message'] as String);
      final begun = await SigningSession.begin(share: share, message: message);
      session = begun.session;
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(begun.round1.wireBytes, flush: true);
      final sessionOut = argResults!['session-out'] as String;
      await File(sessionOut).writeAsBytes(session.toCheckpoint(), flush: true);
      console.success('Round1 wire + session checkpoint written');
      console.detail('signerIndex', '${share.index}');
      console.created(out);
      console.created(sessionOut);
    } on Object catch (error) {
      handleCliError(error);
    } finally {
      session?.dispose();
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

/// Parent command for ML-DSA threshold signing (v2 M3 beta).
final class SignMlDsaCommand extends Command<void> {
  SignMlDsaCommand() {
    addSubcommand(SignMlDsaRunCommand());
    addSubcommand(SignMlDsaPartialCommand());
    addSubcommand(SignMlDsaRound2Command());
    addSubcommand(SignMlDsaRound3Command());
    addSubcommand(SignMlDsaCombineCommand());
    addSubcommand(SignMlDsaVerifyCommand());
  }

  @override
  String get name => 'ml-dsa';

  @override
  String get description => 'ML-DSA threshold signing (C3-PQ, Mithril beta).';
}

/// One-shot ML-DSA threshold sign with optional wire dir export.
final class SignMlDsaRunCommand extends Command<void> {
  SignMlDsaRunCommand() {
    argParser
      ..addMultiOption('share', valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('out', mandatory: true, valueHelp: 'file')
      ..addOption(
        'wire-dir',
        valueHelp: 'dir',
        help: 'Export Round1/2/3 wire messages under round1/, round2/, round3/.',
      );
  }

  @override
  String get name => 'run';

  @override
  String get description =>
      'Threshold-sign with ≥ t ML-DSA shares (Mithril bridge, ML-DSA-44).';

  @override
  Future<void> run() async {
    final shares = <MlDsaShare>[];
    try {
      if (!mithrilBridgeAvailable()) {
        throw SchemeNotImplemented(
          'mithril_bridge not found; build tool/mithril_bridge with cargo',
        );
      }
      final paths = argResults!['share'] as List<String>;
      if (paths.isEmpty) {
        throw ArgumentError('At least one --share file is required');
      }
      shares.addAll([
        for (final path in paths) MlDsaShare.fromBytes(await readBytes(path)),
      ]);
      final message = await readBytes(argResults!['message'] as String);
      final params = shares.first.params;

      final outcome = await MlDsaThresholdSigner.signWithWire(
        shares: shares,
        message: message,
      );
      final wireDir = argResults!['wire-dir'] as String?;
      if (wireDir != null) {
        await writeMlDsaWireMessages(
          baseDir: Directory(wireDir),
          messages: outcome.wireMessages,
        );
        console.detail('wire-messages', '${outcome.wireMessages.length}');
        console.created(wireDir);
      }

      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(outcome.signature, flush: true);
      console.success(
        'ML-DSA threshold signature written (${outcome.signature.length} bytes)',
      );
      console.detail('scheme', params.scheme.name);
      console.detail('signature-hex', bytesToHex(outcome.signature));
      console.created(out);
    } on Object catch (error) {
      handleCliError(error);
    } finally {
      for (final share in shares) {
        share.disposeSecret();
      }
    }
  }
}

/// ML-DSA Round1 from one share (officer-local session checkpoint).
final class SignMlDsaPartialCommand extends Command<void> {
  SignMlDsaPartialCommand() {
    argParser
      ..addOption('share', mandatory: true, valueHelp: 'file')
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addMultiOption('active-party', valueHelp: 'id', help: '0-based party ids (≥ t).')
      ..addOption('out', mandatory: true, valueHelp: 'file')
      ..addOption('session-out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'partial';

  @override
  String get description => 'ML-DSA Round1 wire + officer session checkpoint.';

  @override
  Future<void> run() async {
    MlDsaSigningSession? session;
    MlDsaShare? share;
    try {
      share = MlDsaShare.fromBytes(await readBytes(argResults!['share'] as String));
      final publicKey = MlDsaPublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);
      final activeRaw = argResults!['active-party'] as List<String>;
      if (activeRaw.isEmpty) {
        throw ArgumentError('At least one --active-party id is required');
      }
      final active = activeRaw.map(int.parse).toList()..sort();
      final begun = await MlDsaSigningSession.begin(
        share: share,
        message: message,
        publicKey: publicKey,
        activePartyIdsZeroBased: active,
      );
      session = begun.session;
      await File(argResults!['out'] as String)
          .writeAsBytes(begun.round1.wireBytes, flush: true);
      await File(argResults!['session-out'] as String)
          .writeAsBytes(session.toCheckpoint(), flush: true);
      console.success('ML-DSA Round1 wire + session checkpoint written');
      console.created(argResults!['out'] as String);
      console.created(argResults!['session-out'] as String);
    } on Object catch (error) {
      handleCliError(error);
    } finally {
      session?.dispose();
      share?.disposeSecret();
    }
  }
}

/// ML-DSA Round2 after collecting Round1 wire dir.
final class SignMlDsaRound2Command extends Command<void> {
  SignMlDsaRound2Command() {
    argParser
      ..addOption('session', mandatory: true, valueHelp: 'file')
      ..addOption('round1-dir', mandatory: true, valueHelp: 'dir')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'round2';

  @override
  String get description => 'ML-DSA Round2 reveal from session + Round1 dir.';

  @override
  Future<void> run() async {
    MlDsaSigningSession? session;
    try {
      session = MlDsaSigningSession.fromCheckpoint(
        await readBytes(argResults!['session'] as String),
      );
      final round1 = loadMlDsaWireMessages(
        Directory(argResults!['round1-dir'] as String),
      ).where((m) => m.subKind == MlDsaWireSubKind.round1Commit).toList();
      final wire = await session.completeRound2(round1Messages: round1);
      await File(argResults!['out'] as String).writeAsBytes(wire.wireBytes, flush: true);
      console.success('ML-DSA Round2 wire written');
      console.created(argResults!['out'] as String);
    } on Object catch (error) {
      handleCliError(error);
    } finally {
      session?.dispose();
    }
  }
}

/// ML-DSA Round3 after collecting Round1 + Round2 dirs.
final class SignMlDsaRound3Command extends Command<void> {
  SignMlDsaRound3Command() {
    argParser
      ..addOption('session', mandatory: true, valueHelp: 'file')
      ..addOption('round1-dir', mandatory: true, valueHelp: 'dir')
      ..addOption('round2-dir', mandatory: true, valueHelp: 'dir')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'round3';

  @override
  String get description => 'ML-DSA Round3 response from session + wire dirs.';

  @override
  Future<void> run() async {
    MlDsaSigningSession? session;
    try {
      session = MlDsaSigningSession.fromCheckpoint(
        await readBytes(argResults!['session'] as String),
      );
      final round1 = loadMlDsaWireMessages(
        Directory(argResults!['round1-dir'] as String),
      ).where((m) => m.subKind == MlDsaWireSubKind.round1Commit).toList();
      final round2 = loadMlDsaWireMessages(
        Directory(argResults!['round2-dir'] as String),
      ).where((m) => m.subKind == MlDsaWireSubKind.round2Reveal).toList();
      final wire = await session.completeRound3(
        round1Messages: round1,
        round2Messages: round2,
      );
      await File(argResults!['out'] as String).writeAsBytes(wire.wireBytes, flush: true);
      console.success('ML-DSA Round3 wire written');
      console.created(argResults!['out'] as String);
    } on Object catch (error) {
      handleCliError(error);
    } finally {
      session?.dispose();
    }
  }
}

/// Combines ML-DSA Round2 + Round3 wire dirs into signature.
final class SignMlDsaCombineCommand extends Command<void> {
  SignMlDsaCombineCommand() {
    argParser
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('round2-dir', mandatory: true, valueHelp: 'dir')
      ..addOption('round3-dir', mandatory: true, valueHelp: 'dir')
      ..addMultiOption('active-party', valueHelp: 'id')
      ..addOption('out', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'combine';

  @override
  String get description => 'Combine ML-DSA wire Round2+3 into signature.';

  @override
  Future<void> run() async {
    try {
      final publicKey = MlDsaPublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);
      final activeRaw = argResults!['active-party'] as List<String>;
      if (activeRaw.isEmpty) {
        throw ArgumentError('Provide --active-party ids (0-based, sorted)');
      }
      final active = activeRaw.map(int.parse).toList()..sort();
      final round2 = loadMlDsaWireMessages(
        Directory(argResults!['round2-dir'] as String),
      ).where((m) => m.subKind == MlDsaWireSubKind.round2Reveal).toList();
      final round3 = loadMlDsaWireMessages(
        Directory(argResults!['round3-dir'] as String),
      ).where((m) => m.subKind == MlDsaWireSubKind.round3Response).toList();
      final signature = await combineMlDsaFromWire(
        publicKey: publicKey,
        message: message,
        round2Messages: round2,
        round3Messages: round3,
        activePartyIdsZeroBased: active,
      );
      final out = argResults!['out'] as String;
      await File(out).writeAsBytes(signature, flush: true);
      console.success('Combined ML-DSA signature (${signature.length} bytes)');
      console.detail('signature-hex', bytesToHex(signature));
      console.created(out);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}

/// Verifies ML-DSA threshold signature (exit 0/1).
final class SignMlDsaVerifyCommand extends Command<void> {
  SignMlDsaVerifyCommand() {
    argParser
      ..addOption('public-key', mandatory: true, valueHelp: 'file')
      ..addOption('message', mandatory: true, valueHelp: 'file')
      ..addOption('signature', mandatory: true, valueHelp: 'file');
  }

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify ML-DSA threshold signature via pqforge.';

  @override
  Future<void> run() async {
    try {
      final publicKey = MlDsaPublicKey.fromBytes(
        await readBytes(argResults!['public-key'] as String),
      );
      final message = await readBytes(argResults!['message'] as String);
      final signature = await readBytes(argResults!['signature'] as String);
      final ok = MlDsaThresholdVerifier.verify(
        scheme: publicKey.params.scheme,
        publicKey: publicKey.bytes,
        message: message,
        signature: signature,
      );
      if (ok) {
        console.success('ML-DSA signature valid');
        exitCode = 0;
      } else {
        console.failure('ML-DSA signature invalid');
        exitCode = 1;
      }
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}
