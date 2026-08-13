import 'package:pqthreshold/pqthreshold.dart';

void main() {
  final params = ThresholdParams.tOfN(t: 2, n: 3);
  final ceremonyId = generateCeremonyId();
  validateCeremonyId(ceremonyId);
  // Phase 2+ adds DKG / signing examples — see doc/IMPLEMENTATION.md
  assert(params.t == 2 && params.n == 3);
}
