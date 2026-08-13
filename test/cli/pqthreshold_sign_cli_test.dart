import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _cli(List<String> args) {
  return Process.run(
    'dart',
    ['run', 'pqthreshold', ...args],
    workingDirectory: Directory.current.path,
    runInShell: false,
  );
}

void main() {
  group('pqthreshold CLI signing', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pqth_cli_sign_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('dkg simulate + sign run round-trip', () async {
      final dkgDir = '${tempDir.path}/dkg';
      final dkg = await _cli([
        'dkg',
        'simulate',
        '--t',
        '2',
        '--n',
        '3',
        '--out-dir',
        dkgDir,
      ]);
      expect(dkg.exitCode, 0, reason: dkg.stderr);

      final messageFile = File('${tempDir.path}/msg.bin');
      await messageFile.writeAsBytes([1, 2, 3, 4]);

      final sigPath = '${tempDir.path}/sig.bin';
      final sign = await _cli([
        'sign',
        'run',
        '--share',
        '$dkgDir/share-1.participant-1.pqth',
        '--share',
        '$dkgDir/share-2.participant-2.pqth',
        '--message',
        messageFile.path,
        '--out',
        sigPath,
      ]);
      expect(sign.exitCode, 0, reason: sign.stderr);

      final verify = await _cli([
        'sign',
        'verify',
        '--public-key',
        '$dkgDir/joint.public.pqth',
        '--message',
        messageFile.path,
        '--signature',
        sigPath,
      ]);
      expect(verify.exitCode, 0, reason: verify.stderr);
    });

    test('ceremony run full', () async {
      final result = await _cli(['ceremony', 'run', '--flow', 'full']);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('Full C1→C3→C5'));
    });

    test('vss split and verify', () async {
      final outDir = '${tempDir.path}/vss';
      final split = await _cli([
        'vss',
        'split',
        '--t',
        '2',
        '--n',
        '3',
        '--secret-hex',
        '0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20',
        '--out-dir',
        outDir,
      ]);
      expect(split.exitCode, 0, reason: split.stderr);

      final verify = await _cli([
        'vss',
        'verify',
        '--share',
        '$outDir/share-1.participant-1.pqth',
        '--commitments',
        '$outDir/commitments.blob',
      ]);
      expect(verify.exitCode, 0, reason: verify.stderr);
    });
  });
}
