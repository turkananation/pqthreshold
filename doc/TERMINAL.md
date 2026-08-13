# TERMINAL.md

**pqthreshold** — Terminal workflows, CLI specification, and unified key lifecycle with `pqforge`

Status: formative specification (CLI **not yet implemented** — Phase 1 ships library only)  
Audience: operators, integrators, security reviewers  
**Read with:** [INTEGRATION.md](INTEGRATION.md), [CEREMONIES.md](CEREMONIES.md), pqforge [`doc/CLI.md`](https://github.com/turkananation/pqforge/blob/main/doc/CLI.md)

---

## 1. Purpose

High-assurance key work happens on the terminal: air-gapped officers, CI release gates, admin laptops, and scripted ceremonies. **`pqforge`** already provides a polished terminal for single-party hybrid post-quantum keys (generate, wrap, encrypt, sign, inspect). **`pqthreshold`** adds distributed roots and threshold signing.

This document defines:

1. **How the two CLIs compose** — one custody and UX model across classical, post-quantum, and threshold keys  
2. **What operators run today** vs what is planned  
3. **Terminal UX standards** — the same “super beautiful,” consistent workflow as `pqforge`  
4. **On-disk layout** — where public material, wrapped secrets, shares, and transcripts live  

Implementers: treat this as the operator-facing contract when adding `bin/pqthreshold.dart` (see §8).

---

## 2. Where this is documented today (gap analysis)

| Topic | Document | Coverage |
| ----- | -------- | ---------- |
| Single-party keygen, wrap, encrypt, sign | pqforge `doc/CLI.md` | **Complete** — full command reference |
| Passphrase wrapping (Argon2id + AES-GCM) | pqforge `doc/architecture/KEY_CUSTODY.md` | **Complete** — library + CLI |
| Threshold ceremonies (C1–C6) | [CEREMONIES.md](CEREMONIES.md) | **Complete** — logical flows, not terminal |
| Stack composition (pqforge + pqthreshold) | [INTEGRATION.md](INTEGRATION.md) §3–6 | **Partial** — patterns, no unified terminal runbook |
| PQTH binary objects on disk | [SERIALIZATION.md](SERIALIZATION.md) | **Complete** — bytes, not filenames |
| pqthreshold terminal commands | **This file** | **Specification** — implementation pending |

**Answer:** Key generation, distribution, and management for **single-party** keys are well documented in **pqforge**. Threshold **ceremony logic** is in **CEREMONIES.md** and **INTEGRATION.md**, but there is **no single cross-package terminal runbook** that ties them together. **TERMINAL.md** is that runbook. When the `pqthreshold` executable lands, it must feel like an extension of `pqforge`, not a separate tool.

---

## 3. Unified key lifecycle (cross-package)

Two key **planes** coexist in a typical enclave deployment:

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  PLANE A — Organizational / enclave ROOT (threshold, dealer-less)       │
│  Owner: pqthreshold                                                     │
│  Born:  C1 Root DKG ceremony (no full secret ever on one machine)       │
│  Use:   C3 threshold sign (quorum partials → combined Ed25519 sig)      │
│  Store: PQTH Share + wrapped share secret + Transcript                  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ attests / credentials
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  PLANE B — Member DEVICE keys (single-party hybrid PQC)                 │
│  Owner: pqforge (or raw pqcrypto)                                       │
│  Born:  pqforge keygen on each device                                  │
│  Use:   seal, session, hybrid-sign, day-to-day verify                 │
│  Store: pqforge *.public.json + *.secret.wrapped.json                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Lifecycle stages (same vocabulary everywhere)

| Stage | Single-party (`pqforge`) | Threshold root (`pqthreshold`) |
| ----- | ------------------------ | ------------------------------ |
| **Generate** | `pqforge keygen` | `pqthreshold dkg` (or `ceremony run c1`) |
| **Wrap at rest** | `PqWrappedKey` via passphrase env/file | Share scalar wrapped with **same** Argon2id + AES-GCM model (§5) |
| **Distribute** | Publish public JSON; secrets never leave device | Pairwise / encrypted round messages; shares never on server |
| **Use** | `encrypt`, `sign`, `hybrid-sign`, … | `sign-partial` + `sign-combine` (quorum) |
| **Inspect** | `pqforge inspect` | `pqthreshold inspect` (no decrypt) |
| **Rotate** | New `keygen` + continuity credential | C5 rotation + `ContinuityProof` |
| **Verify** | `verify`, `hybrid-verify` | Combined sig → **`pqforge` / `PqClassical` Ed25519 verify** |

Daily traffic stays on **Plane B**. Roots and high-value actions use **Plane A**. Do not threshold-sign every message.

### 3.2 Recommended operator sequence (greenfield enclave)

```text
1. Officers install both tools:
     dart pub global activate pqforge
     dart pub global activate pqthreshold    # when published

2. Each officer generates a DEVICE identity (Plane B) — optional but typical:
     export PQFORGE_PASSPHRASE='…'
     pqforge keygen --key-id officer-alice --out-dir ~/.pq/keys/alice --passphrase-env PQFORGE_PASSPHRASE

3. Run ROOT DKG (Plane A) — 3-of-5 example:
     pqthreshold ceremony init --t 3 --n 5 --scheme frost-ed25519-v1 --out-dir ./root-ceremony
     # Each officer, on their machine:
     pqthreshold dkg participant \
       --ceremony-dir ./root-ceremony \
       --participant-id alice \
       --share-out ~/.pq/shares/root.share.wrapped.json \
       --passphrase-env PQFORGE_PASSPHRASE

4. Publish joint public key + transcript:
     pqthreshold inspect --in ./root-ceremony/joint.public.pqth
     # Application copies joint public key to enclave directory

5. Issue membership credential (threshold sign over member public bundle):
     pqthreshold sign-partial --share … --message credential.bin --out partial-alice.pqth
     pqthreshold sign-combine --partials ./partials/ --public ./root-ceremony/joint.public.pqth --out credential.sig

6. Member devices operate daily with pqforge only:
     pqforge encrypt … --recipient-public member.kem.public.json
```

Steps 3–5 are **planned CLI shapes** (§7). Until implemented, use library APIs + application transport per [CEREMONIES.md](CEREMONIES.md).

---

## 4. Current state (Phase 1 CLI slice)

| Capability | Terminal today |
| ---------- | ---------------- |
| Params validate / export | **`pqthreshold params`** — flags or `.pqth` file |
| PQTH / ceremony.id inspect | **`pqthreshold inspect`** — no secret unwrap |
| Release verification | `dart run tool/verify.dart full` — developer gate |
| DKG / VSS / threshold sign | Planned Phase 3–5 (`doc/TERMINAL.md` §7) |

Install or run from a checkout:

```bash
dart pub global activate pqthreshold   # when published
# or
dart run pqthreshold --help            # from repo root
```

Phase 1 examples:

```bash
pqthreshold params validate --t 2 --n 3
pqthreshold params export --t 3 --n 5 --out ceremony/params.pqth
pqthreshold inspect --in ceremony/params.pqth

# Developer gate (CI/local)
dart run tool/verify.dart full
```

Pair with **pqforge** for device keys — see §3.2 and pqforge `doc/CLI.md` § Threshold roots.

---

## 5. Custody alignment (must match pqforge)

Threshold **shares are secrets**. Terminal workflows **must not** invent a second wrapping format.

| Material | Format | Passphrase sources |
| -------- | ------ | ------------------ |
| pqforge secret keys | `*.secret.wrapped.json` (`PqWrappedKey`) | `--passphrase-env`, `--passphrase-file`, `--passphrase` |
| pqthreshold share secrets | `*.share.wrapped.json` (same `PqWrappedKey` envelope over PQTH share bytes) | **Same flags and env vars** |
| Public / auditable | `*.public.json` (pqforge) or `*.public.pqth` / `*.pqth` (pqthreshold) | No passphrase |

**Shared environment variable (recommended):** reuse `PQFORGE_PASSPHRASE` for both tools in operator docs so one secret-manager injection covers device keys and threshold shares. Alternatively document `PQTH_PASSPHRASE` as an alias that falls back to `PQFORGE_PASSPHRASE`.

**Rules (non-negotiable):**

1. Never write raw share bytes to disk in production — same warning path as pqforge raw `keygen`.  
2. Unwrap only in process; zeroize after use (`SecretBuffer` / pqforge custody helpers).  
3. Transcripts and public keys may be world-readable; shares may not.  
4. `inspect` commands never decrypt wrapped files.

Reference: pqforge [KEY_CUSTODY.md](https://github.com/turkananation/pqforge/blob/main/doc/architecture/KEY_CUSTODY.md).

---

## 6. On-disk layout (convention)

Use **one directory per ceremony** so operators cannot mix `ceremonyId`s.

```text
root-ceremony-2026-001/
├── ceremony.meta.json          # human metadata: t, n, scheme, started-at (optional)
├── params.pqth                 # ThresholdParams (16 bytes)
├── ceremony.id                 # 16 raw bytes or hex file
├── transport/                  # round messages (file-drop or sync folder)
│   ├── round1/
│   ├── round2/
│   └── round3/
├── joint.public.pqth           # threshold PublicKey
├── transcript.pqth             # sealed transcript
└── officers/
    ├── alice.share.wrapped.json
    └── bob.share.wrapped.json
```

Member device keys (pqforge) live **outside** the ceremony directory, e.g. `~/.pq/keys/<officer>/`.

| Extension | Meaning |
| --------- | ------- |
| `.pqth` | Canonical PQTH binary object ([SERIALIZATION.md](SERIALIZATION.md)) |
| `.public.pqth` | Public threshold material (joint key, params) |
| `.share.wrapped.json` | Wrapped private share |
| `.partial.pqth` | FROST partial signature |
| `.public.json` / `.wrapped.json` | pqforge single-party keys (unchanged) |

---

## 7. Planned `pqthreshold` CLI (specification)

Mirror pqforge patterns: subcommands, grouped `--help`, colored output when TTY, `NO_COLOR` / `--no-color`, exit `0` success / `1` verification or validation failure / `64` usage error.

### 7.1 Command tree (target)

```text
pqthreshold
├── version / --version
├── --help
├── params
│   ├── validate    # t, n, scheme from flags or params.pqth
│   └── export      # write params.pqth
├── inspect         # describe any .pqth / wrapped share / transcript (no secrets)
├── ceremony
│   ├── init        # ceremony id, params, out-dir skeleton
│   └── run         # c1 | c3 | c5 — orchestrated steps with progress UI
├── dkg             # participant subcommands (round1, round2, finalize)
├── vss             # dealer split / verify-share (C2)
├── sign-partial
├── sign-combine
├── sign-verify     # joint pk + message + sig → exit code (pqforge-compatible Ed25519)
├── transcript
│   ├── append      # operator/manual message injection (advanced)
│   └── verify      # hash chain check
└── simulate        # Tier 2 in-process DKG/sign for CI (hidden from default help)
```

### 7.2 UX standards (“super beautiful”)

Match and extend pqforge terminal polish:

| Element | Behavior |
| ------- | -------- |
| **Banner** | On interactive TTY, show compact logo + version + scheme pin on `ceremony` / `dkg` |
| **Progress** | Multi-step ceremonies show `[1/4] Round 1 — contributions` with spinner; `--quiet` for CI |
| **Tables** | `inspect` prints aligned columns (kind, scheme, t-of-n, ceremonyId hex, byte length) |
| **Colors** | Success green, error red, labels cyan; disabled when piped or `NO_COLOR=1` |
| **Confirmations** | Destructive ops (`reconstruct`, raw export) require `--yes` or typed confirm |
| **IDs** | Print `ceremonyId` and participant index prominently after every step |
| **Links** | Footer points to `doc/CEREMONIES.md` section for the running ceremony |

Example target output (illustrative):

```text
pqthreshold ceremony run c1 --ceremony-dir ./root-ceremony --participant alice

  pqthreshold 0.6.0 · FROST Ed25519 v1 · ceremony a4f2…9c01

  [1/4] Setup          ✓ params 3-of-5 · 5 participants
  [2/4] Contributions  ✓ broadcast received (4/4 peers)
  [3/4] Distribution   … waiting for round2 messages (sync transport/)
  [4/4] Finalize       · pending

  Share written: officers/alice.share.wrapped.json
  Transcript:     transcript.pqth (append-only)
```

### 7.3 Transport modes (operator choice)

The CLI does **not** open network sockets by default. Message exchange uses:

| Mode | Use |
| ---- | --- |
| **`--transport dir`** | Shared folder, USB sneakernet, Syncthing (default) |
| **`--transport stdin/out`** | Pipes for scripting |
| **Application API** | Flutter / server app uses Tier 1 `CeremonySession` instead |

Document in runbooks: **how** files move is policy; **what** bytes move is [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md).

---

## 8. Implementation roadmap

| Milestone | Delivers | ROADMAP phase |
| --------- | -------- | ------------- |
| **`params` / `inspect`** | **Shipped** — `bin/pqthreshold.dart` | Phase 1 |
| `vss split/verify` | Dealer ceremony C2 | Phase 2 |
| `dkg participant`, `transcript verify` | C1 on terminal | Phase 3 |
| `sign-partial/combine/verify` | C3 + pqforge-compatible verify | Phase 4 |
| `ceremony run c1/c5`, continuity | Full operator workflows | Phase 5 |

Add to `pubspec.yaml` when the first operator commands ship:

```yaml
executables:
  pqthreshold: pqthreshold
```

**Status:** `executables` is configured; Phase 1 commands are `params` and `inspect`. DKG/signing commands follow Phases 3–5.

Document new commands in this file and cross-link from pqforge `doc/CLI.md` (“Threshold roots” section).

---

## 9. pqforge commands beside threshold work

Operators often run both tools in one session. Keep these pqforge commands in runbooks ([pqforge CLI.md](https://github.com/turkananation/pqforge/blob/main/doc/CLI.md)):

| Task | Command |
| ---- | ------- |
| Device hybrid keygen | `pqforge keygen --out-dir … --passphrase-env PQFORGE_PASSPHRASE` |
| Verify threshold-produced credential | `pqforge verify` or Ed25519 path on raw 64-byte sig |
| Seal officer-to-officer messages | `pqforge encrypt --recipient-public …` |
| Inspect unknown file | `pqforge inspect --in …` then `pqthreshold inspect --in …` |

Combined FROST signatures are **standard Ed25519**. After `pqthreshold sign-combine`, verification may use pqforge/classical verify with the **joint** public key bytes — no threshold-specific verifier in pqforge required ([INTEGRATION.md](INTEGRATION.md) §4.3).

---

## 10. Security notes for terminal use

1. Run root ceremonies on **dedicated machines** or air-gapped hosts when policy requires ([CEREMONIES.md](CEREMONIES.md) §5).  
2. Do not store multiple officers’ wrapped shares in one `officers/` tree on a **single** laptop except in Tier 2 simulation.  
3. Prefer `--passphrase-env` over `--passphrase` (shell history).  
4. Archive `transcript.pqth` to an append-only log; never archive share secrets.  
5. `simulate` subcommand is **Tier 2** — hide from default help; print a warning banner if invoked.

---

## 11. Cross-references

| Need | Document |
| ---- | -------- |
| Ceremony logic | [CEREMONIES.md](CEREMONIES.md) |
| Application integration | [INTEGRATION.md](INTEGRATION.md) |
| Wire bytes | [PROTOCOL_MESSAGES.md](PROTOCOL_MESSAGES.md), [SERIALIZATION.md](SERIALIZATION.md) |
| Single-party CLI | pqforge `doc/CLI.md` |
| Key wrapping | pqforge `doc/architecture/KEY_CUSTODY.md` |
| CI / dev verify | [TOOLING.md](TOOLING.md) |
| Public API (library) | [API.md](API.md) |

---

## 12. Document control

| Version | Change |
| ------- | ------ |
| 2026-08-13 | Initial terminal spec; unified lifecycle with pqforge; CLI planned Phase 3–5 |
