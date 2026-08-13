# Test vectors

JSON test vectors for `pqthreshold` live here, organized by protocol area.

**Full specification:** [doc/TEST_VECTORS.md](../../doc/TEST_VECTORS.md)

## Layout

| Directory | Phase | Contents |
| --------- | ----- | -------- |
| `feldman/` | 2 | Feldman VSS split / verify / reconstruct |
| `dkg/` | 3 | Simulated multi-party DKG outputs |
| `frost/` | 4 | FROST signing round-trip + combined signature |
| `ceremony/` | 5–6 | C5 rotation + continuity proof |

## Status

All v1 vector files for `frostEd25519V1` are present. Regenerate with:

```bash
dart run tool/generate_feldman_vectors.dart   # if present
dart run tool/generate_dkg_vectors.dart
dart run tool/generate_frost_vectors.dart
dart run tool/generate_rotation_vectors.dart
```
