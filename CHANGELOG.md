## 0.1.0

- Planning release: formative architecture, security, ceremony, and integration docs.
- Locked v1 scheme stack (FROST Ed25519, Feldman VSS, Gennaro DKG) in `doc/SCHEMES.md`.
- Added implementer index (`doc/INDEX.md`), protocol specs, params, test vector plan, implementation guide, tooling, release checklist.
- CI (`.github/workflows/ci.yml`) and `tool/verify.dart` release gate.
- ADRs for scheme selection, runtime dependencies, and serialization format.
- Implementation scaffold only; no cryptographic functionality yet.
