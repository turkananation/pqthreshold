# Test vectors

JSON test vectors for `pqthreshold` live here, organized by protocol area.

**Full specification:** [doc/TEST_VECTORS.md](../../doc/TEST_VECTORS.md)

## Layout

| Directory | Phase | Contents |
| --------- | ----- | -------- |
| `feldman/` | 2 | Feldman VSS split / verify / reconstruct |
| `dkg/` | 3 | Simulated multi-party DKG outputs |
| `frost/` | 4 | FROST signing round-trip + combined signature |

## Status

Vector **files** are added when each phase is implemented. Until then, directories may be empty — tests use inline fixtures in Phase 1.

## Rules

- Format: `pqthreshold-test-vector-v1` JSON ([TEST_VECTORS.md](../../doc/TEST_VECTORS.md) §3).
- Hex: lowercase, no `0x` prefix.
- **Test-only secrets only** — never production key material.

## Generate (future)

```bash
dart run tool/generate_vectors.dart   # not yet implemented
```
