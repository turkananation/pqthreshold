import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

void main() {
  group('ThresholdParams.tOfN', () {
    test('accepts valid 2-of-3', () {
      final p = ThresholdParams.tOfN(t: 2, n: 3);
      expect(p.t, 2);
      expect(p.n, 3);
      expect(p.scheme, SchemeId.frostEd25519V1);
    });

    test('accepts boundary 1-of-1 (tests only)', () {
      final p = ThresholdParams.tOfN(t: 1, n: 1);
      expect(p.t, 1);
      expect(p.n, 1);
    });

    test('accepts boundary 255-of-255', () {
      final p = ThresholdParams.tOfN(t: 255, n: 255);
      expect(p.n, 255);
    });

    test('rejects t < 1', () {
      expect(
        () => ThresholdParams.tOfN(t: 0, n: 3),
        throwsA(
          isA<InvalidParams>().having(
            (e) => e.message,
            'message',
            contains('t must be >= 1'),
          ),
        ),
      );
    });

    test('rejects n < 1', () {
      expect(
        () => ThresholdParams.tOfN(t: 1, n: 0),
        throwsA(isA<InvalidParams>()),
      );
    });

    test('rejects t > n', () {
      expect(
        () => ThresholdParams.tOfN(t: 4, n: 3),
        throwsA(
          isA<InvalidParams>().having(
            (e) => e.message,
            'message',
            contains('t must be <= n'),
          ),
        ),
      );
    });

    test('rejects n > 255', () {
      expect(
        () => ThresholdParams.tOfN(t: 2, n: 256),
        throwsA(
          isA<InvalidParams>().having(
            (e) => e.message,
            'message',
            contains('n must be <= 255'),
          ),
        ),
      );
    });
  });

  group('ThresholdParams equality', () {
    test('equal params compare equal', () {
      final a = ThresholdParams.tOfN(t: 3, n: 5);
      final b = ThresholdParams.tOfN(t: 3, n: 5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ThresholdParams serialization', () {
    test('round-trip preserves values', () {
      final original = ThresholdParams.tOfN(t: 3, n: 7);
      final decoded = ThresholdParams.fromBytes(original.toBytes());
      expect(decoded, equals(original));
    });

    test('canonical bytes are deterministic', () {
      final a = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      final b = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      expect(a, equals(b));
    });

    test('wrong length throws SerializationError', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      expect(
        () => ThresholdParams.fromBytes(bytes.sublist(0, bytes.length - 1)),
        throwsA(isA<SerializationError>()),
      );
    });

    test('invalid magic throws SerializationError', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      bytes[0] = 0x00;
      expect(
        () => ThresholdParams.fromBytes(bytes),
        throwsA(isA<SerializationError>()),
      );
    });

    test('unsupported version throws SerializationError', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      bytes[4] = 0x02;
      expect(
        () => ThresholdParams.fromBytes(bytes),
        throwsA(isA<SerializationError>()),
      );
    });

    test('wrong kind throws SerializationError', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      bytes[5] = 0x02; // Share kind
      expect(
        () => ThresholdParams.fromBytes(bytes),
        throwsA(isA<SerializationError>()),
      );
    });

    test('semantic invalid t-of-n in payload throws InvalidParams', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      bytes[8] = 0;
      bytes[9] = 5;
      expect(
        () => ThresholdParams.fromBytes(bytes),
        throwsA(isA<InvalidParams>()),
      );
    });

    test('maxParticipants mismatch throws SerializationError', () {
      final bytes = ThresholdParams.tOfN(t: 2, n: 3).toBytes();
      // maxParticipants uint32 BE at offset 12 (after 8-byte header + t + n).
      bytes[12] = 0;
      bytes[13] = 0;
      bytes[14] = 0;
      bytes[15] = 100;
      expect(
        () => ThresholdParams.fromBytes(bytes),
        throwsA(isA<SerializationError>()),
      );
    });
  });
}
