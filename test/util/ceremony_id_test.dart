import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

void main() {
  group('validateCeremonyId', () {
    test('accepts 16 non-zero bytes', () {
      final id = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
      expect(() => validateCeremonyId(id), returnsNormally);
    });

    test('rejects wrong length', () {
      expect(
        () => validateCeremonyId(Uint8List(15)),
        throwsA(isA<InvalidParams>()),
      );
    });

    test('rejects all-zero id', () {
      expect(
        () => validateCeremonyId(Uint8List(16)),
        throwsA(isA<InvalidParams>()),
      );
    });
  });

  group('generateCeremonyId', () {
    test('returns 16 non-zero bytes', () {
      final id = generateCeremonyId();
      expect(id.length, ceremonyIdLength);
      expect(id.any((b) => b != 0), isTrue);
    });
  });

  group('SecretBuffer', () {
    test('zeroizes on dispose', () {
      final material = Uint8List.fromList([1, 2, 3, 4]);
      final copy = Uint8List.fromList(material);
      final buffer = SecretBuffer(material);
      expect(buffer.bytes, equals(copy));
      buffer.dispose();
      expect(material.every((b) => b == 0), isTrue);
      expect(
        () => buffer.bytes,
        throwsA(isA<StateError>()),
      );
    });
  });
}
