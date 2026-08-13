import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('pqthreshold_example.dart runs without stack overflow', () async {
    final result = await Process.run(
      'dart',
      ['run', 'example/pqthreshold_example.dart'],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stderr: ${result.stderr}\nstdout: ${result.stdout}',
    );
    expect(result.stdout, contains('Example OK'));
    expect(result.stdout, contains('[C1]'));
    expect(result.stdout, contains('[C3]'));
    expect(result.stdout, contains('[C5]'));
  });
}
