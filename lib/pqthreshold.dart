/// Threshold cryptography and distributed key-management for Dart.
///
/// v1 schemes: FROST (Ed25519), Feldman VSS, Gennaro DKG — see `doc/SCHEMES.md`.
///
/// Runtime dependencies:
/// * [pqforge](https://pub.dev/packages/pqforge) — crypto
/// * [swissarmyknife](https://pub.dev/packages/swissarmyknife) — structure
library;

export 'src/errors/threshold_exception.dart';
export 'src/params/scheme_id.dart';
export 'src/params/threshold_params.dart';
export 'src/util/ceremony_id.dart';

/// PQTH header parsing for durable objects (Phase 1+).
export 'src/serialization/pqth_header.dart';

/// Best-effort sensitive buffer wipe (Phase 1+).
export 'src/util/secret_buffer.dart';

/// Verifiable secret sharing and threshold key material (Phase 2+).
export 'src/sharing/share.dart';
export 'src/sharing/verifiable_secret_sharing.dart';

/// Distributed key generation (Phase 3+).
export 'src/dkg/ceremony_session.dart';
export 'src/dkg/dkg_message.dart';
export 'src/transcript/transcript.dart';
