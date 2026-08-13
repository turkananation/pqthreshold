# ADR 003: Serialization format

**Status:** Accepted  
**Date:** 2026-08-13  
**Deciders:** pqthreshold maintainers

## Context

Open decision #3 in `doc/ARCHITECTURE.md`: durable objects need a versioned format with domain separation. Options included CBOR, JSON, protobuf, and custom binary layouts.

Constraints:

- Deterministic encoding for the same logical value
- Reuse existing length-prefixed conventions where possible (`PqBytes` in pqforge)
- No new serialization dependency
- Fail closed on version / scheme mismatch

## Decision

Use a **custom binary layout** with:

- Fixed 8-byte header: `PQTH` magic + `ver` + `kind` + `scheme`
- Payload fields encoded with **`PqBytes.lengthPrefixed`** and big-endian integers
- Domain-separation string registry for protocol hashes (see `doc/SERIALIZATION.md`)
- JSON limited to optional debug helpers, not durable storage

Initial format version byte: **`0x01`**.

## Consequences

### Positive

- No CBOR/protobuf dependency
- Consistent with pqforge envelope field encoding patterns
- Explicit kind bytes prevent cross-type confusion

### Negative

- Custom format requires careful documentation and round-trip tests
- External language bindings must implement the spec manually

## Alternatives considered

| Alternative | Rejected because |
| ----------- | ---------------- |
| CBOR | Extra dependency; canonical CBOR is easy to get wrong |
| JSON primary | Not canonical; risky for crypto objects |
| Protobuf | Schema tooling overhead; overkill for v1 |

## References

- `doc/SERIALIZATION.md`
