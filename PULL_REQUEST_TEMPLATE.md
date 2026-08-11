<!--
  pqthreshold — Pull Request Template
  Thank you for contributing. Please complete every section that applies.
  PRs that change cryptography, share formats, or ceremony behavior require extra scrutiny.
-->

## Summary

<!-- 1–3 sentences: what this PR does and why -->

## Type of change

- [ ] Bug fix (non-breaking)
- [ ] New feature / API addition
- [ ] Breaking change (fix / serialization / scheme behavior)
- [ ] Refactor (no intentional behavior change)
- [ ] Documentation only
- [ ] Tests only
- [ ] Tooling / CI / meta
- [ ] Security hardening

## Related issues

<!-- Link issues, e.g. Fixes #123, Relates to #456 -->

-

## Cryptographic / security impact

<!-- Required for any change that touches crypto, shares, transcripts, or ceremonies -->

- [ ] No change to cryptographic behavior or share/signature formats
- [ ] Changes cryptographic logic or parameters (explain below)
- [ ] Changes serialization / versioned formats (explain migration)
- [ ] Changes ceremony flow or transcript contents
- [ ] Touches randomness, zeroization, or fail-closed error paths

**Details (if any box above except the first is checked):**

<!-- What changed, which schemes/APIs, residual risks, claim-boundary impact -->

## Scheme / component affected

- [ ] `params`
- [ ] `sharing` (VSS)
- [ ] `dkg`
- [ ] `signing` (threshold signatures)
- [ ] `ceremony`
- [ ] `transcript`
- [ ] `errors` / `util`
- [ ] Public barrel / exports
- [ ] Docs only (`ARCHITECTURE`, `SECURITY`, `CEREMONIES`, `INTEGRATION`, README)

## Behavior checklist

- [ ] Fail-closed: invalid shares / partials / transcripts still error (no partial secrets)
- [ ] Threshold invariant preserved: `< t` shares cannot reconstruct or produce a valid combined signature
- [ ] Ceremony IDs / domain separation respected (no cross-ceremony mixing)
- [ ] No private share material logged or written into transcripts
- [ ] Public API docs updated if signatures or types changed
- [ ] `SECURITY.md` claim boundaries still accurate (or PR updates them)

## Serialization & compatibility

- [ ] No durable format change
- [ ] Format version bumped and migration notes added
- [ ] Old fixtures still tested (or explicitly dropped with justification)

## Tests

- [ ] Unit tests added/updated
- [ ] Negative tests (insufficient shares, inconsistent partials, bad transcript)
- [ ] Round-trip / threshold boundary tests (`t-1` fails, `t` succeeds)
- [ ] Integration / multi-party simulation tests (if ceremony or DKG touched)
- [ ] Vectors updated (if applicable)

**Test commands run locally:**

```bash
dart analyze
dart test
# dart run tool/verify.dart   # if present
```

## Documentation

- [ ] README updated (if user-facing)
- [ ] `ARCHITECTURE.md` updated (if structure changed)
- [ ] `CEREMONIES.md` updated (if flows changed)
- [ ] `INTEGRATION.md` updated (if composition guidance changed)
- [ ] `SECURITY.md` updated (if threats, assumptions, or claims changed)
- [ ] CHANGELOG entry added under Unreleased / appropriate version
- [ ] Dartdoc on public APIs

## Breaking changes

<!-- Delete if none. Otherwise list migration steps for callers. -->

-

## Security / disclosure

- [ ] This PR does **not** fix a vulnerability that requires coordinated disclosure
- [ ] This PR fixes a vulnerability (do **not** discuss exploit details in public PR text; follow `SECURITY.md` reporting process)

## Checklist before request for review

- [ ] I have read `CONTRIBUTING.md` and `SECURITY.md`
- [ ] I have not committed secrets, real shares, or private keys
- [ ] CI is green (or failures explained)
- [ ] PR title is clear and conventional (e.g. `feat(dkg): …`, `fix(signing): …`, `docs: …`)

---

**Reviewer notes (optional)**

<!-- Anything you want reviewers to focus on -->
```text

**Suggested file location:**  
`.github/PULL_REQUEST_TEMPLATE.md`  
(or `.github/PULL_REQUEST_TEMPLATE/default.md` if you use multiple templates)

**Optional short PR title convention** (add to `CONTRIBUTING.md`):

```text
feat(dkg): ...
fix(signing): ...
refactor(sharing): ...
docs(security): ...
test(ceremony): ...
chore(ci): ...
