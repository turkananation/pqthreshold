import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

void main() {
  test('takes ownership and wipes the input after copying', () {
    final input = Uint8List.fromList([1, 2, 3]);
    final secret = SecretBuffer(input);

    expect(input, everyElement(0));
    input[0] = 9;

    expect(secret.bytes, orderedEquals([1, 2, 3]));
    secret.dispose();
  });

  test('returns a defensive snapshot', () {
    final secret = SecretBuffer(Uint8List.fromList([1, 2, 3]));
    final snapshot = secret.bytes;

    snapshot[0] = 9;

    expect(secret.bytes, orderedEquals([1, 2, 3]));
    secret.dispose();
  });

  test('rejects access after disposal', () {
    final secret = SecretBuffer(Uint8List.fromList([1, 2, 3]));
    secret.dispose();

    expect(() => secret.bytes, throwsA(isA<StateError>()));
  });

  test('disposal is idempotent', () {
    final secret = SecretBuffer(Uint8List.fromList([1, 2, 3]));

    secret.dispose();
    expect(() => secret.dispose(), returnsNormally);
  });

  test('supports empty secrets', () {
    final secret = SecretBuffer(Uint8List(0));

    expect(secret.bytes, isEmpty);
    secret.dispose();
  });
}
