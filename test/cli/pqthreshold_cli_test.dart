import 'dart:io';

import 'package:pqthreshold/pqthreshold.dart';
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
  group('pqthreshold CLI', () {
    test('help exits zero', () async {
      final result = await _cli(['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('pqthreshold'));
      expect(result.stdout, contains('params'));
      expect(result.stdout, contains('inspect'));
    });

    test('params validate accepts flags', () async {
      final result = await _cli(['params', 'validate', '--t', '2', '--n', '3']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Valid 2-of-3'));
    });

    test('params validate rejects invalid t-of-n', () async {
      final result = await _cli(['params', 'validate', '--t', '5', '--n', '3']);
      expect(result.exitCode, 65);
      expect(result.stderr, contains('t must be <= n'));
    });

    test('params export writes 16-byte pqth file', () async {
      final out = File('${Directory.systemTemp.path}/pqth_cli_params.pqth');
      if (out.existsSync()) out.deleteSync();
      addTearDown(() {
        if (out.existsSync()) out.deleteSync();
      });

      final result = await _cli([
        'params',
        'export',
        '--t',
        '3',
        '--n',
        '5',
        '--out',
        out.path,
      ]);
      expect(result.exitCode, 0);
      expect(out.lengthSync(), 16);

      final roundTrip = await _cli(['params', 'validate', '--in', out.path]);
      expect(roundTrip.exitCode, 0);
      expect(roundTrip.stdout, contains('3-of-5'));
    });

    test('inspect describes exported params', () async {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final out = File('${Directory.systemTemp.path}/pqth_cli_inspect.pqth');
      await out.writeAsBytes(params.toBytes());
      addTearDown(() {
        if (out.existsSync()) out.deleteSync();
      });

      final result = await _cli(['inspect', '--in', out.path]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('ThresholdParams'));
      expect(result.stdout, contains('2-of-3'));
    });

    test('inspect describes ceremony id file', () async {
      final id = generateCeremonyId();
      final out = File('${Directory.systemTemp.path}/pqth_cli_ceremony.id');
      await out.writeAsBytes(id);
      addTearDown(() {
        if (out.existsSync()) out.deleteSync();
      });

      final result = await _cli(['inspect', '--in', out.path]);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Ceremony ID'));
    });

    test('version prints package version', () async {
      final result = await _cli(['version']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('0.5.0'));
    });
  });
}
