/// `params validate` and `params export` commands.
library;

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';

import '../console.dart';
import '../support.dart';

/// Parent command for threshold parameter operations.
final class ParamsCommand extends Command<void> {
  ParamsCommand() {
    addSubcommand(ParamsValidateCommand());
    addSubcommand(ParamsExportCommand());
  }

  @override
  String get name => 'params';

  @override
  String get description =>
      'Validate or export ThresholdParams (PQTH kind 0x01).';
}

/// Validates parameters from flags or a `.pqth` file.
final class ParamsValidateCommand extends Command<void> {
  ParamsValidateCommand() {
    argParser.addOption(
      'in',
      valueHelp: 'file',
      help: 'Existing params.pqth file to validate.',
    );
    addThresholdFlagOptions(argParser, mandatory: false);
  }

  @override
  String get name => 'validate';

  @override
  String get description =>
      'Confirm t-of-n parameters are valid (from flags or --in).';

  @override
  String get usageFooter => usageExamples([
        'pqthreshold params validate --t 2 --n 3',
        'pqthreshold params validate --in ceremony/params.pqth',
      ]);

  @override
  Future<void> run() async {
    try {
      final params = await _resolveParams();
      console.success('Valid ${params.t}-of-${params.n} (${params.scheme.name})');
      printThresholdParams(params);
    } on Object catch (error) {
      handleCliError(error);
    }
  }

  Future<ThresholdParams> _resolveParams() async {
    final input = argResults!['in'] as String?;
    final t = argResults!['t'] as String?;
    final n = argResults!['n'] as String?;

    if (input != null) {
      if (t != null || n != null) {
        throw ArgumentError('Use either --in or --t/--n, not both');
      }
      return ThresholdParams.fromBytes(await readBytes(input));
    }
    if (t == null || n == null) {
      throw ArgumentError('Provide --in or both --t and --n');
    }
    return paramsFromFlags(argResults!);
  }
}

/// Writes canonical ThresholdParams bytes to disk.
final class ParamsExportCommand extends Command<void> {
  ParamsExportCommand() {
    addThresholdFlagOptions(argParser, mandatory: true);
    argParser.addOption(
      'out',
      mandatory: true,
      valueHelp: 'file',
      help: 'Output path for params.pqth (16 bytes).',
    );
  }

  @override
  String get name => 'export';

  @override
  String get description => 'Write canonical ThresholdParams bytes to --out.';

  @override
  String get usageFooter => usageExamples([
        'pqthreshold params export --t 3 --n 5 --out ceremony/params.pqth',
      ]);

  @override
  Future<void> run() async {
    try {
      final params = paramsFromFlags(argResults!);
      final outPath = argResults!['out'] as String;
      final bytes = params.toBytes();
      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      console.success('Exported ${params.t}-of-${params.n} parameters');
      console.created(outPath);
      printThresholdParams(params);
    } on Object catch (error) {
      handleCliError(error);
    }
  }
}
