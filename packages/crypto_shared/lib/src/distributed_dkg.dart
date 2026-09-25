/// Multi-party DKG over a [CeremonyMessageRelay] (production-shaped harness).
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';
import 'package:pqthreshold/pqthreshold.dart';

import 'ceremony_relay.dart';
import 'hex_codec.dart';
import 'officer_dkg_client.dart';

/// Runs C1 with officers communicating only through [relay].
abstract final class DistributedDkgCoordinator {
  /// Executes DKG until all [params.n] participants finalize.
  static Future<
      ({
        List<Share> shares,
        PublicKey publicKey,
        List<Transcript> transcripts,
      })> run({
    required ThresholdParams params,
    required CeremonyMessageRelay relay,
    Uint8List? ceremonyId,
    List<String>? participantIds,
  }) async {
    final cid = ceremonyId ?? generateCeremonyId();
    validateCeremonyId(cid);
    final cidHex = ceremonyIdToHex(cid);
    final ids = participantIds ??
        List.generate(params.n, (i) => 'participant-${i + 1}');

    final clients = [
      for (var i = 1; i <= params.n; i++)
        createOfficerDkgClient(
          params: params,
          ceremonyId: cid,
          ceremonyIdHex: cidHex,
          participantId: ids[i - 1],
          participantIndex: i,
          relay: relay,
          participantIds: ids,
        ),
    ];

    // Bounded rounds: setup + round1 broadcast + round2 pairwise + finalize.
    for (var round = 0; round < params.n + 4; round++) {
      var progressed = false;
      for (final client in clients) {
        if (client.session.isComplete) continue;
        final out = await client.runRound();
        if (out.isNotEmpty) progressed = true;
      }
      if (clients.every((c) => c.session.isComplete)) break;
      if (!progressed && !clients.every((c) => c.session.isComplete)) {
        // Allow one more idle round for delivery before failing.
        continue;
      }
    }

    if (!clients.every((c) => c.session.isComplete)) {
      throw StateError('DKG did not complete over relay');
    }

    final outputs = clients.map((c) => c.finalize()).toList();
    final publicKey = outputs.first.publicKey;
    for (final output in outputs.skip(1)) {
      if (!PqBytes.constantTimeEquals(
        output.publicKey.bytes,
        publicKey.bytes,
      )) {
        throw StateError('Participants derived different joint public keys');
      }
    }

    return (
      shares: [for (final o in outputs) o.share],
      publicKey: publicKey,
      transcripts: [for (final o in outputs) o.transcript],
    );
  }
}
