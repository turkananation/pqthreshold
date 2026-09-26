# ADR 002: Runtime dependencies

**Status:** Accepted (amended 2026-08-13)  
**Date:** 2026-08-13  
**Deciders:** pqthreshold maintainers

## Context

The package needs a **minimal but complete** dependency set:

- **`pqforge`** — shared crypto stack (PQC ecosystem alignment)
- **`swissarmyknife`** — production utilities for state machines, explicit `Result` flow, validation, codecs, and resource lifecycle — essential for auditable multi-round protocols
- **`zeroize`** — best-effort wiping of temporary sensitive byte buffers with deterministic disposal and finalizer fallback

Previously `swissarmyknife` was removed as “unused” during planning. That was premature: ceremony and DKG design depend on structured control flow that should not be hand-rolled.

## Decision

1. **Three runtime dependencies** (no others without ADR):
   - `pqforge: ^0.4.3`
   - `swissarmyknife: ^0.1.0`
   - `zeroize: ^0.1.0`
2. **Do not** add direct `pointycastle`, `pqcrypto`, `cryptography`, or `crypto` to `pubspec.yaml`.
3. **Concern split:**
   - **pqforge** — crypto only (`PqBytes`, `PqRandom`, `PqSymmetricPrimitives`, `PqClassical`; pointycastle last resort per `doc/SCHEMES.md` §4)
   - **swissarmyknife** — engineering structure per `doc/SWISSARMYKNIFE.md`
   - **zeroize** — temporary byte-buffer ownership and wiping; it does not erase immutable `BigInt` values or guarantee removal of GC-copied buffers
4. **Do not** import pqforge envelopes, sessions, or hybrid signers from threshold core.

## Consequences

### Positive

- DKG/ceremony rounds modeled with `StateMachine` + `Result` — reviewable, testable
- Validation and serialization pipelines stay consistent with sibling packages
- Crypto remains centralized in pqforge; no duplicate hash/sign stacks

### Negative

- Two packages to version-align on release
- Contributors must learn the pqforge vs swissarmyknife boundary (documented in two files)

## Dependency graph (v1)

```text
application
   ├── pqthreshold ──► pqforge      (crypto)
   │                ├── swissarmyknife (structure)
   │                └── zeroize      (secret byte lifetimes)
  └── pqforge      (full stack)
```

No circular dependency: neither pqforge nor swissarmyknife depends on pqthreshold.

## Alternatives considered

| Alternative | Rejected because |
| ----------- | ---------------- |
| pqforge only | Hand-rolled state machines and validation are error-prone for DKG |
| swissarmyknife only | No crypto stack |
| Direct pointycastle in pubspec | Bypasses pqforge facades |
| In-tree copy of Result/StateMachine | Duplicates swissarmyknife; same maintainer ecosystem |
| Manual byte overwrites only | Omits zeroize's guarded overwrite and finalizer fallback |

## References

- `doc/SCHEMES.md` §4
- `doc/SWISSARMYKNIFE.md`
- `doc/INTEGRATION.md` §4
