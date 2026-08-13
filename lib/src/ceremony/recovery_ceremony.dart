/// C4 recovery / reconstruction ceremony helpers (`doc/CEREMONIES.md` §8).
library;

import 'dart:typed_data';

import '../errors/threshold_exception.dart';
import '../sharing/share.dart';
import '../sharing/verifiable_secret_sharing.dart';

/// High-privilege C4 reconstruction — explicit, audited secret export.
abstract final class RecoveryCeremony {
  /// Reconstructs the joint secret scalar from ≥ t [shares].
  ///
  /// **Warning:** yields the full secret in one buffer. Use only under strict
  /// policy controls ([CEREMONIES.md](CEREMONIES.md) §8).
  static Uint8List reconstructSecret({required List<Share> shares}) {
    if (shares.isEmpty) {
      throw InsufficientShares('No shares provided for reconstruction');
    }
    assertShareSetConsistent(shares);
    if (shares.length < shares.first.params.t) {
      throw InsufficientShares(
        'Need at least ${shares.first.params.t} shares, got ${shares.length}',
      );
    }
    return VerifiableSecretSharing.reconstruct(shares: shares);
  }
}
