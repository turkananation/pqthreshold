/// pqthreshold — threshold cryptography CLI (Phase 1: params + inspect).
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:pqthreshold/pqthreshold.dart';

import 'src/commands/ceremony_commands.dart';
import 'src/commands/dkg_commands.dart';
import 'src/commands/inspect_command.dart';
import 'src/commands/params_commands.dart';
import 'src/commands/sign_commands.dart';
import 'src/commands/version_command.dart';
import 'src/commands/vss_commands.dart';
import 'src/console.dart';
import 'src/version.g.dart';

const _description =
    'Threshold cryptography for organizational roots — params, DKG, VSS, '
    'threshold signing, and PQTH artifacts. Complements pqforge for device keys.';

const Map<String, List<String>> _groups = {
  'Parameters': ['params'],
  'Ceremonies': ['ceremony', 'dkg', 'vss'],
  'Signing': ['sign'],
  'Artifacts': ['inspect'],
  'Maintenance': ['version'],
};

Future<void> main(List<String> args) async {
  Console.configure(color: resolveColor(args));
  final runner = PqthresholdRunner();

  if (args.isEmpty) {
    runner.printUsage();
    return;
  }

  try {
    await runner.run(args);
  } on UsageException catch (error) {
    console.failure(error.message);
    stderr.writeln();
    stderr.writeln(error.usage);
    exitCode = 64;
  } on ThresholdException catch (error) {
    console.failure(error.message);
    exitCode = 65;
  } on FileSystemException catch (error) {
    final path = error.path == null ? '' : ' (${error.path})';
    console.failure('${error.message}$path');
    exitCode = 66;
  } on FormatException catch (error) {
    console.failure('Malformed input: ${error.message}');
    exitCode = 65;
  } on ArgumentError catch (error) {
    final name = error.name;
    console.failure(
      name == null ? '${error.message}' : '$name: ${error.message}',
    );
    exitCode = 64;
  } on Object catch (error) {
    console.failure('$error');
    exitCode = 70;
  }
}

/// Top-level command runner with grouped, styled help.
final class PqthresholdRunner extends CommandRunner<void> {
  PqthresholdRunner() : super('pqthreshold', _description) {
    argParser
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the pqthreshold version and exit.',
      )
      ..addFlag(
        'color',
        defaultsTo: true,
        help:
            'Use ANSI colors (use --no-color to disable; auto-off when piped).',
      );
    addCommand(ParamsCommand());
    addCommand(InspectCommand());
    addCommand(VersionCommand());
    addCommand(VssCommand());
    addCommand(DkgCommand());
    addCommand(CeremonyCommand());
    addCommand(SignCommand());
  }

  @override
  Future<void> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      console.info('pqthreshold $pqthresholdCliVersion');
      return;
    }
    return super.runCommand(topLevelResults);
  }

  @override
  String get usage {
    final ansi = console.ansi;
    final buffer = StringBuffer()
      ..writeln(console.banner())
      ..writeln();
    for (final line in _wrap(_description, 76)) {
      buffer.writeln('  $line');
    }
    buffer
      ..writeln()
      ..writeln(
        '  ${ansi.bold('Usage:')} ${ansi.cyan('pqthreshold')} '
        '<command> [options]',
      )
      ..writeln(
        '         ${ansi.cyan('pqthreshold')} help <command>'
        '   ${ansi.dim('full help for a command')}',
      );

    final column = _nameColumn();
    final shown = <String>{};
    for (final group in _groups.entries) {
      final names = group.value.where((name) => commands.containsKey(name)).toList();
      if (names.isEmpty) continue;
      buffer
        ..writeln()
        ..writeln('  ${ansi.bold(group.key)}');
      for (final name in names) {
        shown.add(name);
        _writeCommandRow(buffer, ansi, name, column);
      }
    }

    buffer
      ..writeln()
      ..writeln('  ${ansi.bold('Global options')}')
      ..writeln(_indent(argParser.usage, 4))
      ..write(usageFooter);
    return buffer.toString();
  }

  @override
  String get usageFooter {
    final ansi = console.ansi;
    return [
      '',
      '  ${ansi.bold('Examples')}',
      '  ${ansi.gray('# Validate and export ceremony parameters')}',
      '  pqthreshold params validate --t 2 --n 3',
      '  pqthreshold params export --t 3 --n 5 --out params.pqth',
      '  pqthreshold inspect --in params.pqth',
      '',
      '  ${ansi.gray('# Device keys (single-party) — pqforge companion')}',
      '  pqforge keygen --key-id vault --out-dir keys --passphrase-env PQFORGE_PASSPHRASE',
      '',
      '  ${ansi.dim('See doc/TERMINAL.md and pqforge doc/CLI.md for the full stack runbook.')}',
    ].join('\n');
  }

  int _nameColumn() {
    var width = 8;
    for (final name in commands.keys) {
      if (name.length + 2 > width) width = name.length + 2;
    }
    return width;
  }

  void _writeCommandRow(StringBuffer buffer, Ansi ansi, String name, int column) {
    final command = commands[name]!;
    buffer.writeln(
      '  ${ansi.cyan(name.padRight(column))}${command.description}',
    );
  }

  Iterable<String> _wrap(String text, int width) sync* {
    final words = text.split(RegExp(r'\s+'));
    var line = StringBuffer();
    for (final word in words) {
      if (line.isEmpty) {
        line.write(word);
      } else if (line.length + 1 + word.length <= width) {
        line.write(' $word');
      } else {
        yield line.toString();
        line = StringBuffer(word);
      }
    }
    if (line.isNotEmpty) yield line.toString();
  }

  String _indent(String text, int spaces) {
    final pad = ' ' * spaces;
    return text.split('\n').map((line) => '$pad$line').join('\n');
  }
}
