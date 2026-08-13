/// DKG protocol states and events (`doc/PROTOCOL_MESSAGES.md` §3.1).
library;

/// Per-participant DKG lifecycle state.
enum DkgState {
  /// Local polynomial not yet published.
  setup,

  /// Awaiting Round1 packages from all peers.
  round1Broadcast,

  /// Awaiting Round2 shares addressed to this participant.
  round2Distribute,

  /// Optional complaint resolution (v1: verify-only, abort on failure).
  round3Complaints,

  /// Ready to finalize.
  finalized,

  /// Ceremony failed.
  aborted,
}

/// Internal events driving [DkgState] transitions.
enum DkgEvent {
  /// Local polynomial generated; Round1 ready to send.
  localPolyReady,

  /// All Round1 packages received.
  round1Complete,

  /// All Round2 shares received and verified.
  round2Complete,

  /// Unresolvable verification failure.
  abort,

  /// Successful completion.
  complete,
}

/// Maps [DkgState] to the public `round` index on [CeremonySession].
int dkgStateToRound(DkgState state) => switch (state) {
      DkgState.setup => 0,
      DkgState.round1Broadcast => 1,
      DkgState.round2Distribute => 2,
      DkgState.round3Complaints => 3,
      DkgState.finalized => 4,
      DkgState.aborted => 4,
    };
