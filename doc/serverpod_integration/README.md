# Serverpod integration sketch

This folder shows how to wire **pqthreshold** ceremonies into a [Serverpod](https://serverpod.dev) backend without custodying officer shares.

## Layout

| Path | Purpose |
| ---- | ------- |
| [`crypto_shared` on GitHub](https://github.com/turkananation/pqthreshold/tree/main/packages/crypto_shared) | Shared companion package — re-exports, hex codecs, DKG relay, signing jobs, and `ThresholdCeremonyService` |
| `threshold_ceremony_endpoint.dart.example` | Copy into your Serverpod server and adapt auth |

## Principles

- **Server coordinates, officers hold secrets.** Relay `DkgMessage.wireBytes` and collect `PartialSignature` public round material only.
- **Store public PQTH objects:** `PublicKey`, `Transcript`, `ContinuityProof`.
- **Never store** `Share` scalars or wrapped share passphrases in the coordinator DB.

## Quick test (no Serverpod required)

```bash
cd packages/crypto_shared
dart pub get
dart test
```

Tests exercise `DistributedDkgCoordinator`, `ThresholdCeremonyService`, and `SigningJobCoordinator` — the same types your endpoint delegates to.

## Wiring into Serverpod

1. Add a path dependency on `crypto_shared` from your `serverpod_server` package:

   ```yaml
   dependencies:
     crypto_shared:
       path: ../packages/crypto_shared
   ```

2. Register a singleton `ThresholdCeremonyService` (or inject a DB-backed `CeremonyMessageRelay`).

3. Copy `threshold_ceremony_endpoint.dart.example` to  
   `serverpod_server/lib/src/endpoints/threshold_ceremony_endpoint.dart`.

4. Generate protocol and add **authentication** — map `Session` user id to `participantId` / officer role. pqthreshold does not provide identity.

5. Flutter officer app: depend on the same `crypto_shared`, use `OfficerDkgClient` + secure storage for `Share`. See the [companion package on GitHub](https://github.com/turkananation/pqthreshold/tree/main/packages/crypto_shared).

## Related docs

- [doc/GETTING_STARTED.md](../doc/GETTING_STARTED.md) §14 — Flutter / Serverpod integration
- [doc/INTEGRATION.md](../doc/INTEGRATION.md) — transport and custody boundaries
- [doc/CEREMONIES.md](../doc/CEREMONIES.md) — C1 / C3 / C5 flows
