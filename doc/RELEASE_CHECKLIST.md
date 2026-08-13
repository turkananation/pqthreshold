# Release checklist (v1.0)

**pqthreshold** — Gate before tagging `1.0.0`

Use with [ROADMAP.md](ROADMAP.md) Phase 6 and [TOOLING.md](TOOLING.md).

---

## Specification

- [ ] All files in `tool/verify.dart` `_requiredDocs` manifest present
- [ ] [INDEX.md](INDEX.md) reading order matches repository
- [ ] [SECURITY.md](SECURITY.md) Appendix A accurate for shipped code
- [ ] No open protocol ambiguities in [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md)

## Implementation

- [ ] Phases 1–5 complete per [IMPLEMENTATION.md](IMPLEMENTATION.md)
- [ ] Tier 1 API matches [API.md](API.md)
- [ ] Tier 2 APIs live in `testing.dart` only

## Tests

- [ ] `dart run tool/verify.dart full` passes
- [ ] All [TEST_VECTORS.md](TEST_VECTORS.md) §4 criteria pass
- [ ] Property tests: `t-1` fails, `t` succeeds (VSS, signing)
- [ ] DKG simulation: 2-of-3 and 3-of-5 consistent joint public key

## Security

- [ ] Independent cryptographic review completed
- [ ] No secrets in git history (audit sample commits)
- [ ] Claim boundaries in README match [SECURITY.md](SECURITY.md) §6

## Release

- [ ] CHANGELOG 1.0.0 entry
- [ ] Version in `pubspec.yaml` bumped
- [ ] `doc/API.md` stability note updated for 1.0 freeze

---

## Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial v1.0 checklist |
