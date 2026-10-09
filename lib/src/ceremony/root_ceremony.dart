/// C1 root DKG ceremony helpers (`doc/API.md` §4.4).
library;

import 'dart:typed_data';

import '../dkg/ceremony_session.dart';
import '../dkg/dkg_simulator.dart';
import '../params/threshold_params.dart';
import '../sharing/share.dart';
import '../transcript/transcript.dart';

/// Orchestration for dealer-less root generation (C1).
abstract final class RootCeremony {
  /// Tier 1: creates one participant's DKG session.
  static CeremonySession startSession({
    required ThresholdParams params,
    required Uint8List ceremonyId,
    required String participantId,
    required int participantIndex,
    List<String>? participantIds,
  }) => CeremonySession.create(
    params: params,
    ceremonyId: ceremonyId,
    participantId: participantId,
    participantIndex: participantIndex,
    participantIds: participantIds,
  );

  /// In-process C1 simulation — prefer `package:pqthreshold/testing.dart`.
  static Future<
    ({List<Share> shares, PublicKey publicKey, Transcript transcript})
  >
  simulate(
    ThresholdParams params, {
    Uint8List? ceremonyId,
    List<String>? participantIds,
    int? seed,
  }) async {
    // [seed] reserved for deterministic harnesses; wire when needed.
    final outcome = DkgSimulator.run(
      params: params,
      ceremonyId: ceremonyId,
      participantIds: participantIds,
    );
    return (
      shares: outcome.shares,
      publicKey: outcome.publicKey,
      transcript: outcome.transcripts.first,
    );
  }
}
