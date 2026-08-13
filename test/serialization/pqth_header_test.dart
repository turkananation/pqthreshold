import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';
import 'package:pqthreshold/src/serialization/pqth_format.dart';
import 'package:test/test.dart';

void main() {
  group('PqthHeader', () {
    test('decode valid header from ThresholdParams bytes', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      final bytes = params.toBytes();
      final header = PqthHeader.decode(bytes);
      expect(header.version, pqthFormatVersion);
      expect(header.scheme, SchemeId.frostEd25519V1);
    });

    test('encode standalone header is 8 bytes', () {
      final header = PqthHeader.decode(
        ThresholdParams.tOfN(t: 2, n: 3).toBytes(),
      );
      final encoded = header.toBytes();
      expect(encoded.length, pqthHeaderLength);
      expect(encoded.sublist(0, 4), equals([0x50, 0x51, 0x54, 0x48]));
    });

    test('rejects buffer shorter than 8 bytes', () {
      expect(
        () => PqthHeader.decode(Uint8List(4)),
        throwsA(isA<SerializationError>()),
      );
    });

    test('rejects invalid magic', () {
      final bytes = Uint8List.fromList([
        0x00,
        0x51,
        0x54,
        0x48,
        pqthFormatVersion,
        0x01,
        0x00,
        0x01,
      ]);
      expect(
        () => PqthHeader.decode(bytes),
        throwsA(isA<SerializationError>()),
      );
    });

    test('rejects unknown object kind', () {
      final bytes = Uint8List.fromList([
        0x50,
        0x51,
        0x54,
        0x48,
        pqthFormatVersion,
        0x99,
        0x00,
        0x01,
      ]);
      expect(
        () => PqthHeader.decode(bytes),
        throwsA(isA<SerializationError>()),
      );
    });
  });
}
