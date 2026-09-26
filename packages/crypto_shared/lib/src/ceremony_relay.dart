/// DKG message relay — application transport boundary for C1.
library;

import 'dart:typed_data';

/// Relays canonical DKG wire bytes between participants.
///
/// Serverpod implementations persist to DB; Flutter officers call RPC methods
/// that delegate here. **Never** store share secrets on the relay.
abstract interface class CeremonyMessageRelay {
  /// Publishes one outbound DKG envelope.
  Future<void> publish({
    required String ceremonyId,
    required int senderIndex,
    required Uint8List wireBytes,
    int? recipientIndex,
  });

  /// Returns wire bytes addressed to [recipientIndex] (or broadcast if null).
  Future<List<Uint8List>> fetchInbox({
    required String ceremonyId,
    required int recipientIndex,
  });
}

/// In-memory relay for tests and local multi-process prototypes.
final class InMemoryCeremonyRelay implements CeremonyMessageRelay {
  final _messages = <String, List<_RelayEntry>>{};

  @override
  Future<void> publish({
    required String ceremonyId,
    required int senderIndex,
    required Uint8List wireBytes,
    int? recipientIndex,
  }) async {
    _messages
        .putIfAbsent(ceremonyId, () => [])
        .add(
          _RelayEntry(
            senderIndex: senderIndex,
            recipientIndex: recipientIndex,
            wireBytes: Uint8List.fromList(wireBytes),
          ),
        );
  }

  @override
  Future<List<Uint8List>> fetchInbox({
    required String ceremonyId,
    required int recipientIndex,
  }) async {
    final entries = _messages[ceremonyId] ?? const [];
    return [
      for (final entry in entries)
        if (entry.recipientIndex == null ||
            entry.recipientIndex == recipientIndex)
          Uint8List.fromList(entry.wireBytes),
    ];
  }

  /// Clears a ceremony bucket (tests).
  void resetCeremony(String ceremonyId) => _messages.remove(ceremonyId);
}

final class _RelayEntry {
  _RelayEntry({
    required this.senderIndex,
    required this.recipientIndex,
    required this.wireBytes,
  });

  final int senderIndex;
  final int? recipientIndex;
  final Uint8List wireBytes;
}
