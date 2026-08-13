/// Threshold cryptography and distributed key-management for Dart.
///
/// **Planning phase** — see `doc/API.md` for the intended public surface.
/// v1 schemes: FROST (Ed25519), Feldman VSS, Gennaro DKG (`doc/SCHEMES.md`).
///
/// Runtime dependencies:
/// * [pqforge](https://pub.dev/packages/pqforge) — crypto (`PqBytes`, `PqClassical`, …)
/// * [swissarmyknife](https://pub.dev/packages/swissarmyknife) — structure
///   (`StateMachine`, `Result`, `Validator`, …); see `doc/SWISSARMYKNIFE.md`
library;

// Public exports will be added as modules are implemented.
// See doc/API.md for Tier 1 (production) vs Tier 2 (simulation) APIs.
