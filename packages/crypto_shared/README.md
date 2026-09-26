# crypto_shared

Shared integration helpers for applications that combine [`pqthreshold`](https://pub.dev/packages/pqthreshold) and [`pqforge`](https://pub.dev/packages/pqforge).

The package provides the application-facing transport and coordination layer for distributed ceremonies. It is intended for Flutter officer clients, Dart services, and Serverpod coordinators.

## Included

- `CeremonyMessageRelay` and `InMemoryCeremonyRelay` for DKG message transport.
- `OfficerDkgClient` for driving a participant's `CeremonySession` through a relay.
- `DistributedDkgCoordinator` and `DistributedSigningCoordinator` for in-process orchestration.
- `SigningJobCoordinator` and `ThresholdCeremonyService` for coordinator-side job handling.
- Hex codecs and pqforge-aligned share wrapping helpers.

This package does not provide authentication, authorization, durable storage, or a network transport implementation. Applications must provide those boundaries and must never store officer share secrets in the coordinator.

## Installation

```yaml
dependencies:
  crypto_shared: ^1.0.0
```

The package supports Dart VM and native Flutter platforms. It is not Web-compatible because the custody and directory-relay helpers use `dart:io`.

## Typical layout

```text
officer_app/       # Flutter app; stores its own Share securely
serverpod_server/  # coordinator; relays wire messages and collects partials
```

A Serverpod wiring sketch is available in the [repository integration guide](https://github.com/turkananation/pqthreshold/blob/main/doc/serverpod_integration/README.md).

## Security boundary

The relay may carry DKG wire messages and public transcripts, but it must not receive private share scalars or passphrases. Add officer authentication and authorization to every application endpoint. Dispose temporary sensitive byte buffers and use platform secure storage for persistent shares.

## Development

```bash
dart pub get
dart analyze
dart test
```

The source package lives in the [pqthreshold repository](https://github.com/turkananation/pqthreshold/tree/main/packages/crypto_shared).

Because this package lives under the root package's `packages/` pub exclusion,
publish it from an external staging copy:

```bash
bash ../../tool/publish_crypto_shared.sh --dry-run
bash ../../tool/publish_crypto_shared.sh
```

## License

MIT. See [LICENSE](LICENSE).
