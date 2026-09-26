/// Pure-Dart ceremony service — delegate from Serverpod endpoints.
library;

import 'dart:typed_data';

import 'package:pqthreshold/pqthreshold.dart';

import 'ceremony_relay.dart';
import 'hex_codec.dart';
import 'signing_job_coordinator.dart';

/// Coordinator-side API (no share custody).
final class ThresholdCeremonyService {
  ThresholdCeremonyService({CeremonyMessageRelay? relay})
    : relay = relay ?? InMemoryCeremonyRelay(),
      signing = SigningJobCoordinator();

  /// Message relay backing DKG rounds.
  final CeremonyMessageRelay relay;

  /// Active threshold signing jobs.
  final SigningJobCoordinator signing;

  final _publicKeys = <String, Uint8List>{};
  final _transcripts = <String, Uint8List>{};

  /// Officer submits one DKG wire envelope (hex or raw bytes).
  Future<void> submitDkgMessage({
    required String ceremonyIdHex,
    required Uint8List wireBytes,
  }) async {
    final message = DkgMessage.fromBytes(wireBytes);
    await relay.publish(
      ceremonyId: ceremonyIdHex,
      senderIndex: message.senderIndex,
      wireBytes: wireBytes,
      recipientIndex: message.recipientIndex,
    );
  }

  /// Officer fetches DKG inbox for their index.
  Future<List<Uint8List>> fetchDkgInbox({
    required String ceremonyIdHex,
    required int participantIndex,
  }) => relay.fetchInbox(
    ceremonyId: ceremonyIdHex,
    recipientIndex: participantIndex,
  );

  /// Stores published joint public key (PQTH bytes).
  void publishPublicKey({
    required String ceremonyIdHex,
    required Uint8List publicKeyBytes,
  }) {
    _publicKeys[ceremonyIdHex] = Uint8List.fromList(publicKeyBytes);
  }

  /// Stores sealed transcript (PQTH bytes).
  void publishTranscript({
    required String ceremonyIdHex,
    required Uint8List transcriptBytes,
  }) {
    _transcripts[ceremonyIdHex] = Uint8List.fromList(transcriptBytes);
  }

  /// Returns stored public key bytes, if any.
  Uint8List? publicKeyBytes(String ceremonyIdHex) => _publicKeys[ceremonyIdHex];

  /// Returns stored transcript bytes, if any.
  Uint8List? transcriptBytes(String ceremonyIdHex) =>
      _transcripts[ceremonyIdHex];

  /// Verify helper for clients (optional RPC).
  Future<bool> verifyThresholdSignature({
    required Uint8List publicKeyBytes,
    required Uint8List message,
    required Uint8List signature,
  }) {
    final pk = PublicKey.fromBytes(publicKeyBytes);
    return ThresholdSigner.verify(
      publicKey: pk,
      message: message,
      signature: signature,
    );
  }

  /// Parses ceremony id hex for clients.
  Uint8List parseCeremonyId(String ceremonyIdHex) =>
      ceremonyIdFromHex(ceremonyIdHex);
}
