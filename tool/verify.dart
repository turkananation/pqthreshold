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
  'doc/PQ_SCHEMES.md',
  'doc/ML_DSA_THRESHOLD_PROFILE.md',
  'doc/SLH_DSA_THRESHOLD_PROFILE.md',
  'doc/adr/001-scheme-selection.md',
  'doc/adr/002-runtime-dependencies.md',
  'doc/adr/003-serialization-format.md',
  'doc/adr/004-pq-threshold-schemes.md',
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
  'test/scheme',
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
  await _buildMithrilBridgeIfNeeded(root);
  await _runCommand(root, 'dart', ['analyze', '--fatal-infos']);
  await _runCommand(root, 'dart', ['test', '--timeout=2m']);
  await _verifyNestedPackages(root);
}

/// Resolves, analyses and tests each nested package.
///
/// `packages/` is excluded from the root `analysis_options.yaml`, because the
/// root `dart analyze` walks the whole tree and a nested package has no entry in
/// the root package_config.json. These packages are not dropped from the gate as
/// a result: each one gets its own `pub get`, its own analyze, and its own
/// tests here. `crypto_shared` is a separately published package whose source
/// lives in this repository, so it must keep a working gate.
Future<void> _verifyNestedPackages(Directory root) async {
  final packages = Directory('${root.path}/packages');
  if (!packages.existsSync()) return;

  final children =
      packages
          .listSync()
          .whereType<Directory>()
          .where((d) => File('${d.path}/pubspec.yaml').existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final package in children) {
    final name = package.path.split(Platform.pathSeparator).last;
    stdout.writeln('\n=== nested package: $name ===');
    await _runCommand(package, 'dart', ['pub', 'get']);
    await _runCommand(package, 'dart', ['analyze', '--fatal-infos']);
    await _runCommand(package, 'dart', ['test', '--timeout=2m']);
  }
}

Future<void> _buildMithrilBridgeIfNeeded(Directory root) async {
  final bridgeDir = Directory('${root.path}/tool/mithril_bridge');
  final binary = File('${bridgeDir.path}/target/release/mithril_bridge');
  if (binary.existsSync()) {
    stdout.writeln('  mithril_bridge already built.');
    return;
  }
  if (Process.runSync('which', ['cargo']).exitCode != 0) {
    stdout.writeln('  Skipping mithril_bridge (cargo not installed).');
    return;
  }
  stdout.writeln('Building mithril_bridge (ML-DSA M2 tests)...');
  await _runCommand(bridgeDir, 'cargo', ['build', '--release']);
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
  final cryptoShared = Directory('${root.path}/packages/crypto_shared');
  if (cryptoShared.existsSync()) {
    // Already resolved, analysed and tested by _verifyNestedPackages in quick
    // mode; nothing extra to do here.
    stdout.writeln('packages/crypto_shared covered by the quick gate.');
  }
}

Future<void> _runCommand(
  Directory root,
  String executable,
  List<String> args,
) async {
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
