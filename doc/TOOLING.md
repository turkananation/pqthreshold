# TOOLING.md

**pqthreshold** — CI, local verification, and release gates

Status: formative specification  
Audience: implementers, contributors  
Prerequisites: [INDEX.md](INDEX.md), [ROADMAP.md](ROADMAP.md)

---

## 1. Purpose

Defines how to **verify** the repository locally and in CI **before** and **during** implementation. No cryptographic release claims until [TEST_VECTORS.md](TEST_VECTORS.md) acceptance criteria pass ([ROADMAP.md](ROADMAP.md) Phase 6).

---

## 2. Commands (daily development)

```bash
dart pub get
dart analyze
dart test
dart run tool/verify.dart quick
```

| Command | When |
| ------- | ---- |
| `dart analyze` | After every edit |
| `dart test` | After every behavioral change |
| `dart run tool/verify.dart quick` | Before every PR (same as CI) |

---

## 3. `tool/verify.dart` modes

| Mode | Runs | Use |
| ---- | ---- | --- |
| **`quick`** (default) | `pub get` → `dart analyze --fatal-infos` → `dart test` | CI, pre-PR |
| **`docs`** | Manifest check — all required spec files exist | Spec-only PRs, release audit |
| **`full`** | `quick` + `docs` + phase test dirs when present | Pre-release, Phase 2+ |

```bash
dart run tool/verify.dart          # quick
dart run tool/verify.dart docs
dart run tool/verify.dart full
```

### 3.1 Documentation manifest

`docs` / `full` verify paths listed in `tool/verify.dart` (`_requiredDocs`), including:

- All files in [INDEX.md](INDEX.md) §2 reading order
- ADRs, CONTRIBUTING, SECURITY, `test/vectors/README.md`
- [IMPLEMENTATION.md](IMPLEMENTATION.md), this file

If a required doc is removed or renamed, update **`tool/verify.dart`** and [INDEX.md](INDEX.md) in the same PR.

### 3.2 Phase test directories

`full` additionally runs (only if the directory exists):

| Directory | ROADMAP phase |
| --------- | ------------- |
| `test/serialization/` | Phase 1 |
| `test/sharing/` | Phase 2 |
| `test/dkg/` | Phase 3 |
| `test/signing/` | Phase 4 |

Missing directories are skipped with a log line — expected before that phase lands.

---

## 4. Continuous integration

GitHub Actions workflow: **`.github/workflows/ci.yml`**

- Triggers: push and PR to `main`
- Runs: `dart run tool/verify.dart quick`

Future: add `full` on release tags or nightly once Phase 2+ tests exist.

---

## 5. Release gate progression

| Milestone | Required verify |
| --------- | ---------------- |
| Phase 0 (spec only) | `quick` + `docs` |
| Phase 1 landed | `full` (serialization tests) |
| Phase 2–4 landed | `full` + vectors in [TEST_VECTORS.md](TEST_VECTORS.md) |
| v1.0 | `full` + independent review ([ROADMAP.md](ROADMAP.md) Phase 6) |

---

## 6. Future tools (not yet implemented)

| Tool | Phase | Purpose |
| ---- | ----- | ------- |
| `tool/generate_vectors.dart` | 2+ | Regenerate JSON under `test/vectors/` |
| `tool/bench_dkg.dart` | 3+ | Web `n` limit benchmarks |

Document new tools here when added.

---

## 7. Cross-references

| Topic | Document |
| ----- | -------- |
| What to implement | [IMPLEMENTATION.md](IMPLEMENTATION.md) |
| Test vectors | [TEST_VECTORS.md](TEST_VECTORS.md) |
| Contributor setup | [CONTRIBUTING.md](../CONTRIBUTING.md) |

---

## 8. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial tooling spec; verify.dart + CI |
