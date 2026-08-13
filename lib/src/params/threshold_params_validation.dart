/// Internal validation for [ThresholdParams].
library;

import 'package:meta/meta.dart';
import 'package:swissarmyknife/swissarmyknife.dart';

import 'scheme_id.dart';

/// Validates `(t, n)` for [SchemeId.frostEd25519V1].
///
/// Spec: `doc/PARAMS.md` §3.2, §6.
@internal
Validator<(int t, int n)> frostEd25519V1ParamsValidator() {
  final maxN = SchemeId.frostEd25519V1.maxParticipants;
  return Validator<(int, int)>()
      .custom((p) => p.$1 >= 1, 't must be >= 1')
      .custom((p) => p.$2 >= 1, 'n must be >= 1')
      .custom((p) => p.$1 <= p.$2, 't must be <= n')
      .custom((p) => p.$2 <= maxN, 'n must be <= $maxN for frostEd25519V1');
}

/// Validates [SchemeId] is supported in v1 public API.
@internal
Validator<SchemeId> supportedSchemeValidator() {
  return Validator<SchemeId>().custom(
    (scheme) => scheme == SchemeId.frostEd25519V1,
    'Unsupported scheme in v1',
  );
}
