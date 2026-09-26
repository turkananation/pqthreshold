import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold_experimental.dart';
import 'package:test/test.dart';

void main() {
  group('SchemeId', () {
    test('frostEd25519V1 wire ordinal is 1', () {
      expect(SchemeId.frostEd25519V1.wireOrdinal, 0x0001);
      expect(SchemeId.frostEd25519V1.maxParticipants, 255);
      expect(SchemeId.frostEd25519V1.isPostQuantumThreshold, isFalse);
    });

    test('v2 PQ ordinals match ADR-004', () {
      expect(SchemeId.mlDsa44ThresholdV1.wireOrdinal, 0x0002);
      expect(SchemeId.mlDsa65ThresholdV1.wireOrdinal, 0x0003);
      expect(SchemeId.mlDsa87ThresholdV1.wireOrdinal, 0x0004);
      expect(SchemeId.slhDsa128fThresholdV1.wireOrdinal, 0x0005);
      expect(SchemeId.hybridFrostMlDsa65V1.wireOrdinal, 0x0006);
      expect(SchemeId.mlDsa65ThresholdV1.maxParticipants, 8);
      expect(SchemeId.mlDsa65ThresholdV1.isPostQuantumThreshold, isTrue);
    });

    test('fromWireOrdinal round-trips registry', () {
      for (final scheme in SchemeId.values) {
        expect(schemeIdFromWireOrdinal(scheme.wireOrdinal), scheme);
      }
    });

    test('fromWireOrdinal rejects unknown', () {
      expect(
        () => schemeIdFromWireOrdinal(99),
        throwsA(isA<SerializationError>()),
      );
    });
  });

  group('ThresholdParams PQ bounds', () {
    test('mlDsa65 accepts n=8', () {
      final params = ThresholdParams.tOfN(
        t: 3,
        n: 8,
        scheme: SchemeId.mlDsa65ThresholdV1,
      );
      expect(params.n, 8);
      expect(ThresholdParams.fromBytes(params.toBytes()), params);
    });

    test('mlDsa65 rejects n=9', () {
      expect(
        () => ThresholdParams.tOfN(
          t: 2,
          n: 9,
          scheme: SchemeId.mlDsa65ThresholdV1,
        ),
        throwsA(isA<InvalidParams>()),
      );
    });
  });

  group('SchemeCapabilities', () {
    test('frostEd25519V1 is production', () {
      expect(
        SchemeCapabilities.milestone(SchemeId.frostEd25519V1),
        SchemeMilestone.production,
      );
      expect(
        SchemeCapabilities.supports(
          SchemeId.frostEd25519V1,
          ThresholdCeremonyKind.thresholdSign,
        ),
        isTrue,
      );
    });

    test('mlDsa65 is beta; signing via bridge not yet supported', () {
      expect(
        SchemeCapabilities.milestone(SchemeId.mlDsa65ThresholdV1),
        SchemeMilestone.beta,
      );
      expect(
        () => SchemeCapabilities.requireProductionCeremony(
          SchemeId.mlDsa65ThresholdV1,
          ThresholdCeremonyKind.rootDkg,
        ),
        throwsA(isA<SchemeNotImplemented>()),
      );
    });
  });

  group('MlDsaThresholdVerifier', () {
    test('verify accepts pqforge single-party signature', () {
      final keyPair = PqSignaturePrimitives.generateKeyPair(
        PqSignatureAlgorithm.mlDsa65,
      );
      final message = Uint8List.fromList([1, 2, 3, 4]);
      final signature = PqSignaturePrimitives.sign(
        PqSignatureAlgorithm.mlDsa65,
        keyPair.secretKey,
        message,
      );
      expect(
        MlDsaThresholdVerifier.verify(
          scheme: SchemeId.mlDsa65ThresholdV1,
          publicKey: keyPair.publicKey,
          message: message,
          signature: signature,
        ),
        isTrue,
      );
    });

    test('verify rejects wrong signature length', () {
      final keyPair = PqSignaturePrimitives.generateKeyPair(
        PqSignatureAlgorithm.mlDsa65,
      );
      expect(
        MlDsaThresholdVerifier.verify(
          scheme: SchemeId.mlDsa65ThresholdV1,
          publicKey: keyPair.publicKey,
          message: Uint8List.fromList([0]),
          signature: Uint8List(64),
        ),
        isFalse,
      );
    });
  });
}
