# Contributing to pqthreshold

Thank you for contributing. This project handles threshold cryptography — changes require careful review.

## Prerequisites

- Dart SDK `^3.12.2` (see `pubspec.yaml`)
- Read **[doc/INDEX.md](doc/INDEX.md)** before implementing
- Familiarity with `doc/SECURITY.md`, `doc/ARCHITECTURE.md`, and `doc/SCHEMES.md`

## Development setup

```bash
git clone https://github.com/turkananation/pqthreshold.git
cd pqthreshold
dart pub get
dart analyze
dart test
dart run tool/verify.dart quick    # same as CI
dart run tool/verify.dart full     # before Phase 1+ / release
```

## Project phase

Status: planning — **Phase 0 complete** ([ROADMAP.md](doc/ROADMAP.md)). Start coding with [IMPLEMENTATION.md](doc/IMPLEMENTATION.md) §4 after `dart run tool/verify.dart full` passes.

## Dependency policy

- **Two runtime dependencies:** `pqforge` (crypto) and `swissarmyknife` (structure). See `doc/adr/002-runtime-dependencies.md`.
- **pqforge-first** for all cryptography: `PqBytes`, `PqRandom`, `PqSymmetricPrimitives`, `PqClassical`; pointycastle only when pqforge lacks the API (`doc/SCHEMES.md` §4).
- **swissarmyknife** for DKG state machines, internal `Result` flow, `Validator`, `CodecPipeline`, disposal, tuples — full map in `doc/SWISSARMYKNIFE.md`.
- Do **not** add `pointycastle`, `pqcrypto`, or `cryptography` to `pubspec.yaml`.
- Do **not** import pqforge envelopes, sessions, or hybrid signers from threshold core.

## Code layout

```text
lib/
  pqthreshold.dart          # public barrel (Tier 1)
  testing.dart              # Tier 2 simulation APIs (when added)
  src/
    params/ sharing/ dkg/ signing/ ceremony/ transcript/ errors/ util/ scheme/
doc/
  ARCHITECTURE.md SCHEMES.md SERIALIZATION.md API.md SECURITY.md ...
  adr/
test/
```

## Pull requests

Use the PR template checklist. Required for crypto changes:

- Fail-closed behavior preserved
- Threshold invariant tests (`t-1` fails, `t` succeeds)
- No secrets or real shares in commits
- Update `doc/SECURITY.md` if claims change
- CHANGELOG entry under `[Unreleased]` or the target version

### PR title convention

```text
feat(dkg): ...
fix(signing): ...
refactor(sharing): ...
docs(security): ...
test(ceremony): ...
chore(ci): ...
```

## Adding a new scheme

1. ADR in `doc/adr/`
2. Update `doc/SCHEMES.md` and `doc/SECURITY.md`
3. New `SchemeId` value and serialization kind rules
4. Full test vectors and property tests at least as strict as v1

## Security issues

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md) at the repository root. Do not open public issues for unfixed crypto vulnerabilities.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
