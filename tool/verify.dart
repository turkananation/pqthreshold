// pqthreshold release gate — run locally and in CI.
//
// Usage:
//   dart run tool/verify.dart quick   # analyze + test (default)
//   dart run tool/verify.dart docs    # required documentation manifest
//   dart run tool/verify.dart full    # quick + docs (+ phase tests when present)
//
// See doc/TOOLING.md

import 'dart:io';

const _requiredDocs = [
  'doc/INDEX.md',
  'doc/GETTING_STARTED.md',
  'doc/ARCHITECTURE.md',
  'doc/SCHEMES.md',
  'doc/PARAMS.md',
  'doc/SERIALIZATION.md',
  'doc/FROST_PROFILE.md',
  'doc/PROTOCOL_MESSAGES.md',
  'doc/API.md',
  'doc/SWISSARMYKNIFE.md',
  'doc/TEST_VECTORS.md',
  'doc/TOOLING.md',
  'doc/IMPLEMENTATION.md',
  'doc/RELEASE_CHECKLIST.md',
  'doc/REVIEW_CHECKLIST.md',
  'doc/SECURITY.md',
  'doc/CEREMONIES.md',
  'doc/INTEGRATION.md',
  'doc/TERMINAL.md',
  'doc/ROADMAP.md',
  'doc/adr/001-scheme-selection.md',
  'doc/adr/002-runtime-dependencies.md',
  'doc/adr/003-serialization-format.md',
  'test/vectors/README.md',
  'CONTRIBUTING.md',
  'SECURITY.md',
];

/// Optional test directories — run when they exist (added per ROADMAP phases).
const _phaseTestDirs = [
  'test/serialization',
  'test/cli',
  'test/sharing',
  'test/dkg',
  'test/signing',
  'test/ceremony',
  'test/example',
];

Future<void> main(List<String> args) async {
  final mode = args.isEmpty ? 'quick' : args.first;
  final root = _repoRoot();

  stdout.writeln('pqthreshold verify ($mode) — root: ${root.path}');

  switch (mode) {
    case 'quick':
      await _runQuick(root);
    case 'docs':
      _runDocsCheck(root);
    case 'full':
      await _runQuick(root);
      _runDocsCheck(root);
      await _runPhaseTests(root);
    default:
      stderr.writeln('Unknown mode: $mode');
      stderr.writeln('Usage: dart run tool/verify.dart [quick|docs|full]');
      exit(64);
  }

  stdout.writeln('verify: OK');
}

Directory _repoRoot() {
  final script = Platform.script.toFilePath();
  final toolDir = File(script).parent;
  return toolDir.parent;
}

Future<void> _runQuick(Directory root) async {
  await _runCommand(root, 'dart', ['pub', 'get']);
  await _runCommand(root, 'dart', ['analyze', '--fatal-infos']);
  await _runCommand(root, 'dart', ['test']);
}

void _runDocsCheck(Directory root) {
  stdout.writeln('Checking required documentation...');
  final missing = <String>[];
  for (final relative in _requiredDocs) {
    final file = File('${root.path}/$relative');
    if (!file.existsSync()) {
      missing.add(relative);
    }
  }
  if (missing.isNotEmpty) {
    stderr.writeln('Missing required files:');
    for (final path in missing) {
      stderr.writeln('  - $path');
    }
    exit(1);
  }
  stdout.writeln('  ${_requiredDocs.length} required paths present.');
}

Future<void> _runPhaseTests(Directory root) async {
  for (final dir in _phaseTestDirs) {
    final path = '${root.path}/$dir';
    if (Directory(path).existsSync()) {
      stdout.writeln('Running phase tests: $dir');
      await _runCommand(root, 'dart', ['test', dir]);
    } else {
      stdout.writeln('Skipping (not yet present): $dir');
    }
  }
}

Future<void> _runCommand(Directory root, String executable, List<String> args) async {
  stdout.writeln('\n> $executable ${args.join(' ')}');
  final result = await Process.start(
    executable,
    args,
    workingDirectory: root.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Command failed with exit code $exitCode');
    exit(exitCode);
  }
}
