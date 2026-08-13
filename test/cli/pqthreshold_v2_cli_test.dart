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
  group('pqthreshold v2 CLI', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pqth_v2_cli_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('distributed FROST partial → round2 → combine', () async {
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
      await messageFile.writeAsBytes([5, 6, 7]);

      final round1Dir = '${tempDir.path}/round1';
      final round2Dir = '${tempDir.path}/round2';
      await Directory(round1Dir).create();
      await Directory(round2Dir).create();

      for (final i in [1, 2]) {
        final sharePath = Directory(dkgDir)
            .listSync()
            .whereType<File>()
            .map((f) => f.path)
            .firstWhere((p) => p.contains('share-$i.'));
        final sessionPath = '${tempDir.path}/session-$i.bin';
        final round1Out = '$round1Dir/from-$i.wire';
        final partial = await _cli([
          'sign',
          'partial',
          '--share',
          sharePath,
          '--message',
          messageFile.path,
          '--out',
          round1Out,
          '--session-out',
          sessionPath,
        ]);
        expect(partial.exitCode, 0, reason: partial.stderr);
      }

      for (final i in [1, 2]) {
        final sessionPath = '${tempDir.path}/session-$i.bin';
        final round2Out = '$round2Dir/round2-from-$i.wire';
        final round2 = await _cli([
          'sign',
          'round2',
          '--session',
          sessionPath,
          '--public-key',
          '$dkgDir/joint.public.pqth',
          '--round1-dir',
          round1Dir,
          '--out',
          round2Out,
        ]);
        expect(round2.exitCode, 0, reason: round2.stderr);
      }

      final sigPath = '${tempDir.path}/sig.bin';
      final combine = await _cli([
        'sign',
        'combine',
        '--public-key',
        '$dkgDir/joint.public.pqth',
        '--message',
        messageFile.path,
        '--round1-dir',
        round1Dir,
        '--round2-dir',
        round2Dir,
        '--out',
        sigPath,
      ]);
      expect(combine.exitCode, 0, reason: combine.stderr);

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

    test('dkg participant step completes 2-of-3 via transport dir', () async {
      final ceremonyDir = '${tempDir.path}/ceremony';
      await Directory(ceremonyDir).create();

      for (var step = 0; step < 20; step++) {
        for (var index = 1; index <= 3; index++) {
          final result = await _cli([
            'dkg',
            'participant',
            'step',
            '--t',
            '2',
            '--n',
            '3',
            '--ceremony-dir',
            ceremonyDir,
            '--participant-id',
            'p$index',
            '--index',
            '$index',
          ]);
          expect(result.exitCode, 0, reason: result.stderr);
        }
        final allShares = [1, 2, 3].every(
          (i) => File('$ceremonyDir/officers/p$i/share.pqth').existsSync(),
        );
        if (allShares) break;
      }

      expect(File('$ceremonyDir/joint.public.pqth').existsSync(), isTrue);
      for (var index = 1; index <= 3; index++) {
        expect(
          File('$ceremonyDir/officers/p$index/share.pqth').existsSync(),
          isTrue,
        );
      }
    });
  });
}
