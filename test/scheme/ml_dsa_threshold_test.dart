import 'dart:io';
import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold_experimental.dart';
import 'package:pqthreshold/testing_experimental.dart';
import 'package:test/test.dart';

void main() {
  final bridgePath = 'tool/mithril_bridge/target/release/mithril_bridge';

  group('MlDsa threshold M2', () {
    test(
      'mithril bridge available in dev tree',
      () {
        expect(
          mithrilBridgeAvailable(overridePath: bridgePath),
          isTrue,
          reason: 'Run: cd tool/mithril_bridge && cargo build --release',
        );
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );

    test(
      '2-of-3 threshold sign verifies via pqforge',
      () async {
        final params = ThresholdParams.tOfN(
          t: 2,
          n: 3,
          scheme: SchemeId.mlDsa44ThresholdV1,
        );
        final message = Uint8List.fromList('pqthreshold ml-dsa m2'.codeUnits);

        final root = await MlDsaRootCeremony.simulate(
          params,
          mithrilBridgePath: bridgePath,
        );
        expect(
          root.publicKey.bytes.length,
          PqSignatureAlgorithm.mlDsa44.publicKeyBytes,
        );

        final signature = await MlDsaThresholdSigningCeremony.simulate(
          shares: root.shares,
          message: message,
          mithrilBridgePath: bridgePath,
        );

        expect(
          MlDsaThresholdVerifier.verify(
            scheme: SchemeId.mlDsa44ThresholdV1,
            publicKey: root.publicKey.bytes,
            message: message,
            signature: signature,
          ),
          isTrue,
        );

        for (final share in root.shares) {
          share.disposeSecret();
        }
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );

    test(
      'MlDsaShare PQTH round-trip',
      () async {
        final params = ThresholdParams.tOfN(
          t: 2,
          n: 3,
          scheme: SchemeId.mlDsa44ThresholdV1,
        );
        final root = await MlDsaRootCeremony.simulate(
          params,
          mithrilBridgePath: bridgePath,
        );
        final share = root.shares.first;
        expect(MlDsaShare.fromBytes(share.toBytes()), share);
        for (final s in root.shares) {
          s.disposeSecret();
        }
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );

    test(
      'mlDsa65 signing throws until Mithril-65',
      () async {
        final params = ThresholdParams.tOfN(
          t: 2,
          n: 3,
          scheme: SchemeId.mlDsa65ThresholdV1,
        );
        expect(
          () => MlDsaThresholdSimulator.run(
            params: params,
            message: Uint8List.fromList([1]),
            mithrilBridgePath: bridgePath,
          ),
          throwsA(isA<SchemeNotImplemented>()),
        );
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );
  });

  group('MlDsa threshold M3 wire', () {
    test('MlDsaSigningMessage round-trip', () {
      final params = ThresholdParams.tOfN(
        t: 2,
        n: 3,
        scheme: SchemeId.mlDsa44ThresholdV1,
      );
      final ceremonyId = PqBytes.randomBytes(16);
      final sessionId = PqBytes.randomBytes(32);
      final commitment = PqBytes.randomBytes(32);
      final original = MlDsaSigningMessage.round1(
        params: params,
        ceremonyId: ceremonyId,
        senderIndex: 1,
        sessionId: sessionId,
        commitmentHash: commitment,
      );
      final decoded = MlDsaSigningMessage.fromBytes(original.wireBytes);
      expect(decoded.kind, MlDsaWireKind.round1);
      expect(decoded.subKind, MlDsaWireSubKind.round1Commit);
      expect(decoded.scheme, SchemeId.mlDsa44ThresholdV1);
      expect(decoded.senderIndex, 1);
      expect(decoded.payload, commitment);
      expect(decoded.transcriptHash(), original.transcriptHash());
    });

    test(
      'signWithWire exports verifiable signature and wire dir',
      () async {
        final params = ThresholdParams.tOfN(
          t: 2,
          n: 3,
          scheme: SchemeId.mlDsa44ThresholdV1,
        );
        final message = Uint8List.fromList(
          'pqthreshold ml-dsa m3 wire'.codeUnits,
        );
        final root = await MlDsaRootCeremony.simulate(
          params,
          mithrilBridgePath: bridgePath,
        );
        final outcome = await MlDsaThresholdSigner.signWithWire(
          shares: root.shares.take(2).toList(),
          message: message,
          mithrilBridgePath: bridgePath,
        );
        expect(outcome.wireMessages.length, 6);
        expect(outcome.sessionId.length, 32);

        for (final wire in outcome.wireMessages) {
          expect(
            MlDsaSigningMessage.fromBytes(wire.wireBytes).payload,
            wire.payload,
          );
        }

        expect(
          MlDsaThresholdVerifier.verify(
            scheme: params.scheme,
            publicKey: root.publicKey.bytes,
            message: message,
            signature: outcome.signature,
          ),
          isTrue,
        );

        final tmp = await Directory.systemTemp.createTemp('pqth-ml-dsa-wire');
        addTearDown(() => tmp.deleteSync(recursive: true));
        await writeMlDsaWireMessages(
          baseDir: tmp,
          messages: outcome.wireMessages,
        );
        final loaded = loadMlDsaWireMessages(tmp);
        expect(loaded.length, outcome.wireMessages.length);

        for (final share in root.shares) {
          share.disposeSecret();
        }
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );

    test(
      'distributed three-round session matches signWithWire',
      () async {
        final params = ThresholdParams.tOfN(
          t: 2,
          n: 3,
          scheme: SchemeId.mlDsa44ThresholdV1,
        );
        final message = Uint8List.fromList(
          'pqthreshold ml-dsa distributed'.codeUnits,
        );
        final root = await MlDsaRootCeremony.simulate(
          params,
          mithrilBridgePath: bridgePath,
        );
        final signers = root.shares.take(2).toList();
        final active = signers.map((s) => s.mithrilPartyId).toList()..sort();

        final round1 = <MlDsaSigningMessage>[];
        final sessions = <MlDsaSigningSession>[];
        for (final share in signers) {
          final begun = await MlDsaSigningSession.begin(
            share: share,
            message: message,
            publicKey: root.publicKey,
            activePartyIdsZeroBased: active,
            mithrilBridgePath: bridgePath,
          );
          round1.add(begun.round1);
          sessions.add(begun.session);
        }

        final round2 = <MlDsaSigningMessage>[];
        for (final session in sessions) {
          round2.add(await session.completeRound2(round1Messages: round1));
        }

        final round3 = <MlDsaSigningMessage>[];
        for (final session in sessions) {
          round3.add(
            await session.completeRound3(
              round1Messages: round1,
              round2Messages: round2,
            ),
          );
        }

        final signature = await combineMlDsaFromWire(
          publicKey: root.publicKey,
          message: message,
          round2Messages: round2,
          round3Messages: round3,
          activePartyIdsZeroBased: active,
          mithrilBridgePath: bridgePath,
        );

        expect(
          MlDsaThresholdVerifier.verify(
            scheme: params.scheme,
            publicKey: root.publicKey.bytes,
            message: message,
            signature: signature,
          ),
          isTrue,
        );

        for (final session in sessions) {
          session.dispose();
        }
        for (final share in root.shares) {
          share.disposeSecret();
        }
      },
      skip: !mithrilBridgeAvailable(overridePath: bridgePath)
          ? 'no bridge'
          : false,
    );
  });
}
