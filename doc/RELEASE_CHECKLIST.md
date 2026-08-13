# Release checklist (v1.0)

**pqthreshold** — Gate before tagging `1.0.0`

Use with [ROADMAP.md](ROADMAP.md) Phase 6 and [TOOLING.md](TOOLING.md).  
Independent review: [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md).

---

## Specification

- [x] All files in `tool/verify.dart` `_requiredDocs` manifest present
- [x] [INDEX.md](INDEX.md) reading order matches repository
- [ ] [SECURITY.md](SECURITY.md) Appendix A accurate for shipped code (reviewer sign-off)
- [x] No open protocol ambiguities in [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md)

## Implementation

- [x] Phases 1–10 complete per [IMPLEMENTATION.md](IMPLEMENTATION.md) (except operator review sign-off)
- [x] Tier 1 API matches [API.md](API.md)
- [x] Tier 2 APIs live in `testing.dart` only

## Tests

- [x] `dart run tool/verify.dart full` passes
- [x] All [TEST_VECTORS.md](TEST_VECTORS.md) §4 criteria pass
- [x] Property tests: `t-1` fails, `t` succeeds (VSS, signing)
- [x] DKG simulation: 2-of-3 and 3-of-5 consistent joint public key

## Security

- [ ] Independent cryptographic review completed ([REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md))
- [ ] No secrets in git history (audit sample commits)
- [x] Claim boundaries in README match [SECURITY.md](SECURITY.md) §6

## Release

- [x] CHANGELOG 1.0.0 entry finalized
- [x] Version in `pubspec.yaml` bumped to `1.0.0`
- [x] `doc/API.md` stability note updated for 1.0 freeze

---

## Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial v1.0 checklist |
| 2026-08-13 | 1.0.0 release items complete; operator review items remain |
