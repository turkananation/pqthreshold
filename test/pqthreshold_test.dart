import 'package:pqthreshold/pqthreshold.dart';
import 'package:test/test.dart';

void main() {
  group('ThresholdException', () {
    test('subtypes are distinct sealed classes', () {
      expect(const InvalidParams('x'), isA<ThresholdException>());
      expect(const SerializationError('x'), isA<ThresholdException>());
    });

    test('toString includes runtime type', () {
      expect(const InvalidParams('bad t').toString(), 'InvalidParams: bad t');
    });
  });

  group('package smoke', () {
    test('ThresholdParams is constructible from public API', () {
      final params = ThresholdParams.tOfN(t: 2, n: 3);
      expect(params.toBytes().length, 16);
    });
  });
}
