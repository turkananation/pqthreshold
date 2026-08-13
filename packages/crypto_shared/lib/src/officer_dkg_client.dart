/// One officer's DKG session driven through a [CeremonyMessageRelay].
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

import 'ceremony_relay.dart';

/// Drives [CeremonySession] rounds via a relay (Flutter ↔ Serverpod pattern).
final class OfficerDkgClient {
  OfficerDkgClient({
    required this._session,
    required this._relay,
    required this._ceremonyIdHex,
  });

  final CeremonySession _session;
  final CeremonyMessageRelay _relay;
  final String _ceremonyIdHex;

  /// Current session bound to this officer.
  CeremonySession get session => _session;

  /// Pulls inbox from relay, advances state, publishes outbox.
  Future<List<DkgMessage>> runRound() async {
    final inboxBytes = await _relay.fetchInbox(
      ceremonyId: _ceremonyIdHex,
      recipientIndex: _session.participantIndex,
    );
    final inbox = inboxBytes.map(DkgMessage.fromBytes).toList();
    final outbox = _session.processInbox(inbox);
    for (final message in outbox) {
      await _relay.publish(
        ceremonyId: _ceremonyIdHex,
        senderIndex: message.senderIndex,
        wireBytes: message.wireBytes,
        recipientIndex: message.recipientIndex,
      );
    }
    return outbox;
  }

  /// Finalizes when [CeremonySession.isComplete].
  ({Share share, PublicKey publicKey, Transcript transcript}) finalize() =>
      _session.finalize();
}

/// Factory for a new officer client.
OfficerDkgClient createOfficerDkgClient({
  required ThresholdParams params,
  required Uint8List ceremonyId,
  required String ceremonyIdHex,
  required String participantId,
  required int participantIndex,
  required CeremonyMessageRelay relay,
  List<String>? participantIds,
}) {
  final session = RootCeremony.startSession(
    params: params,
    ceremonyId: ceremonyId,
    participantId: participantId,
    participantIndex: participantIndex,
    participantIds: participantIds,
  );
  return OfficerDkgClient(
    session: session,
    relay: relay,
    ceremonyIdHex: ceremonyIdHex,
  );
}
