/// Threshold cryptography and distributed key-management for Dart.
///
/// v1 schemes: FROST (Ed25519), Feldman VSS, Gennaro DKG — see `doc/SCHEMES.md`.
/// v2 registry: ML-DSA / SLH-DSA threshold profiles — see `doc/PQ_SCHEMES.md`.
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

/// Threshold signing (Phase 4+).
export 'src/signing/frost_signing_message.dart';
export 'src/signing/partial_signature.dart';
export 'src/signing/signing_session.dart';
export 'src/signing/threshold_signer.dart';

/// Ceremony orchestration (Phase 5+).
export 'src/ceremony/continuity_proof.dart';
export 'src/ceremony/dealer_ceremony.dart';
export 'src/ceremony/recovery_ceremony.dart';
export 'src/ceremony/root_ceremony.dart';
export 'src/ceremony/rotation_ceremony.dart';
export 'src/ceremony/threshold_signing_ceremony.dart';

/// Post-quantum scheme registry and verify helpers (v2 M1+).
export 'src/ceremony/ml_dsa_root_ceremony.dart';
export 'src/ceremony/ml_dsa_threshold_signing_ceremony.dart';
export 'src/scheme/ml_dsa/ml_dsa_share.dart';
export 'src/scheme/ml_dsa/ml_dsa_threshold_signer.dart';
export 'src/scheme/ml_dsa/mithril_bridge.dart' show mithrilBridgeAvailable;
export 'src/scheme/ml_dsa/ml_dsa_profile.dart';
export 'src/scheme/ml_dsa/ml_dsa_threshold_verifier.dart';
export 'src/scheme/ml_dsa/ml_dsa_signing_message.dart'
    hide mlDsaMessagesFromWireSignJson;
export 'src/scheme/scheme_capabilities.dart';
