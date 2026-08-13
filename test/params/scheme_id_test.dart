import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

void main() {
  group('SchemeId', () {
    test('frostEd25519V1 wire ordinal is 1', () {
      expect(SchemeId.frostEd25519V1.wireOrdinal, 0x0001);
      expect(SchemeId.frostEd25519V1.maxParticipants, 255);
    });

    test('fromWireOrdinal accepts 1', () {
      expect(schemeIdFromWireOrdinal(1), SchemeId.frostEd25519V1);
    });

    test('fromWireOrdinal rejects unknown', () {
      expect(
        () => schemeIdFromWireOrdinal(99),
        throwsA(isA<SerializationError>()),
      );
    });
  });
}
