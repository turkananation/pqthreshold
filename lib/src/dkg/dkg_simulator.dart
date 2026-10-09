/// In-process DKG runner shared by Tier 2 helpers.
library;

import 'dart:typed_data';

import 'package:pqforge/pqforge.dart';

import '../params/threshold_params.dart';
import '../sharing/share.dart';
import '../transcript/transcript.dart';
import '../util/ceremony_id.dart';
import 'ceremony_session.dart';
import 'dkg_message.dart';

/// Runs a full DKG ceremony in one process.
abstract final class DkgSimulator {
  /// Simulates C1 for all [params.n] participants.
  static ({
    List<Share> shares,
    PublicKey publicKey,
    List<Transcript> transcripts,
  })
  run({
    required ThresholdParams params,
    Uint8List? ceremonyId,
    List<String>? participantIds,
  }) {
    final cid = ceremonyId ?? generateCeremonyId();
    validateCeremonyId(cid);
    final ids =
        participantIds ??
        List.generate(params.n, (i) => 'participant-${i + 1}');
    if (ids.length != params.n) {
      throw ArgumentError('participantIds length must equal n=${params.n}');
    }

    final sessions = [
      for (var i = 1; i <= params.n; i++)
        CeremonySession.create(
          params: params,
          ceremonyId: cid,
          participantId: ids[i - 1],
          participantIndex: i,
          participantIds: ids,
        ),
    ];

    var round1 = <DkgMessage>[];
    for (final session in sessions) {
      round1.addAll(session.processInbox(const []));
    }

    var round2 = <DkgMessage>[];
    for (final session in sessions) {
      round2.addAll(session.processInbox(round1));
    }

    for (final session in sessions) {
      final forMe = round2.where(
        (m) => m.recipientIndex == session.participantIndex,
      );
      session.processInbox(forMe);
    }

    final outputs = sessions.map((s) => s.finalize()).toList();
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
