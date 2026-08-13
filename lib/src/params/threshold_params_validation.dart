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

/// Validates `(t, n)` for v2 PQ small-set schemes (`n ≤ 8`, ADR-004).
@internal
Validator<(int t, int n)> pqThresholdSmallSetParamsValidator(SchemeId scheme) {
  final maxN = scheme.maxParticipants;
  return Validator<(int, int)>()
      .custom((p) => p.$1 >= 1, 't must be >= 1')
      .custom((p) => p.$2 >= 1, 'n must be >= 1')
      .custom((p) => p.$1 <= p.$2, 't must be <= n')
      .custom((p) => p.$2 <= maxN, 'n must be <= $maxN for $scheme');
}

/// Validates [SchemeId] is a known registry entry (v1 production + v2 alpha).
@internal
Validator<SchemeId> supportedSchemeValidator() {
  return Validator<SchemeId>().custom(
    (scheme) => switch (scheme) {
      SchemeId.frostEd25519V1 ||
      SchemeId.mlDsa44ThresholdV1 ||
      SchemeId.mlDsa65ThresholdV1 ||
      SchemeId.mlDsa87ThresholdV1 ||
      SchemeId.slhDsa128fThresholdV1 ||
      SchemeId.hybridFrostMlDsa65V1 =>
        true,
    },
    'Unknown scheme',
  );
}
